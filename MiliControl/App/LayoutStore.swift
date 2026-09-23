//
//  LayoutStore.swift
//  MiliControl
//
//  Owns the user's grid layout: loads/saves it, and keeps it reconciled with
//  the desktops that actually exist (new desktops land at the end of the last
//  row; removed ones disappear; nothing else moves).
//

import Foundation
import Combine
import os

final class LayoutStore: ObservableObject {

    @Published private(set) var layout: GridLayout

    private let desktops: DesktopStore
    private let defaults: UserDefaults
    private var cancellable: AnyCancellable?
    private static let storageKey = "grid.layout.v1"
    private let log = Logger(subsystem: "com.mili.MiliControl", category: "layout")

    init(desktops: DesktopStore, defaults: UserDefaults = .standard) {
        self.desktops = desktops
        self.defaults = defaults

        let keys = desktops.desktops.map(\.key)
        let saved = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(GridLayout.self, from: $0) }
        if keys.isEmpty {
            // Window server returned nothing (can happen very early at login):
            // keep the saved arrangement untouched and reconcile later.
            layout = saved ?? GridLayout()
        } else if let saved = saved {
            layout = saved.reconciled(with: keys)
            save()
        } else {
            layout = GridLayout.chunked(keys, perRow: 4)
            save()
        }

        cancellable = desktops.$desktops
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] list in self?.reconcile(with: list) }
    }

    /// Applies an edit and persists it.
    func update(_ change: (inout GridLayout) -> Void) {
        var copy = layout
        change(&copy)
        guard copy != layout else { return }
        layout = copy
        save()
    }

    /// Back to "system order, 4 per row".
    func resetToDefault() {
        let fresh = GridLayout.chunked(desktops.desktops.map(\.key), perRow: 4)
        guard fresh != layout else { return }
        layout = fresh
        save()
    }

    /// The grid restricted to desktops that exist and that macOS can switch to
    /// by shortcut (Desktops 1–9). This is what navigation uses.
    func navigableRows() -> [[String]] {
        let reachable = Set(desktops.desktops
            .filter { SymbolicHotKeys.switchableDesktops.contains($0.number) }
            .map(\.key))
        return layout.rows.map { $0.filter(reachable.contains) }
    }

    private func reconcile(with list: [Desktop]) {
        // An empty list is a transient window-server state (sleep/wake,
        // display changes) — never let it wipe the user's arrangement.
        guard !list.isEmpty else { return }
        let reconciled = layout.reconciled(with: list.map(\.key))
        guard reconciled != layout else { return }
        log.debug("Layout reconciled with \(list.count, privacy: .public) desktops")
        layout = reconciled
        save()
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(layout), forKey: Self.storageKey)
        } catch {
            log.error("Saving layout failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
