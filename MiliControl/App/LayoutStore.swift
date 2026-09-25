//
//  LayoutStore.swift
//  MiliControl
//
//  Owns the user's grid layout: loads/saves it, and keeps it reconciled with
//  the spaces that actually exist — desktops and fullscreen apps. New desktops
//  land at the end of the last row, a new fullscreen app right after the
//  space it came from; removed desktops disappear; a fullscreen app that's
//  out of fullscreen keeps its (hidden) slot until it returns. Nothing else
//  moves.
//
//  With "Keep each row in macOS order" on (the default), every row is also
//  kept in macOS's own order (Mission Control's strip, fullscreen apps
//  included) after each change — including reorders made in Mission
//  Control — so moving right always slides right.
//

import Foundation
import Combine
import os

final class LayoutStore: ObservableObject {

    @Published private(set) var layout: GridLayout

    private let desktops: DesktopStore
    private let prefs: Preferences
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private static let storageKey = "grid.layout.v1"
    private let log = Logger(subsystem: "com.mili.MiliControl", category: "layout")

    init(desktops: DesktopStore, prefs: Preferences, defaults: UserDefaults = .standard) {
        self.desktops = desktops
        self.prefs = prefs
        self.defaults = defaults

        let keys = desktops.orderedKeys
        let saved = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(GridLayout.self, from: $0) }
        if keys.isEmpty {
            // Window server returned nothing (can happen very early at login):
            // keep the saved arrangement untouched and reconcile later.
            layout = saved ?? GridLayout()
        } else {
            layout = saved.map { Self.reconcile($0, with: keys) } ?? GridLayout.chunked(keys, perRow: 4)
            layout = arranged(layout)
            save()
        }

        // Desktops added, removed, or reordered in Mission Control; apps
        // entering or leaving fullscreen.
        desktops.$desktops.map { _ in () }
            .merge(with: desktops.$fullscreens.map { _ in () })
            .dropFirst(2)
            .receive(on: RunLoop.main)
            // `@Published` fires before storing; read the store on the next pass.
            .sink { [weak self] in DispatchQueue.main.async { self?.reconcile() } }
            .store(in: &cancellables)

        // Turning native order on sorts the rows right away.
        prefs.$rowsFollowNativeOrder
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // `@Published` fires before storing; apply on the next pass.
                DispatchQueue.main.async { self?.update { _ in } }
            }
            .store(in: &cancellables)
    }

    /// Whether the order inside a row is macOS's (and can't be dragged).
    var followsNativeOrder: Bool { prefs.rowsFollowNativeOrder }

    /// Applies an edit (then native ordering, if on) and persists it.
    func update(_ change: (inout GridLayout) -> Void) {
        var copy = layout
        change(&copy)
        copy = arranged(copy)
        guard copy != layout else { return }
        layout = copy
        save()
    }

    /// Back to "system order, 4 per row".
    func resetToDefault() {
        let fresh = GridLayout.chunked(desktops.orderedKeys, perRow: 4)
        guard fresh != layout else { return }
        layout = fresh
        save()
    }

    /// The grid restricted to spaces that exist and that MiliControl can
    /// switch to (Desktops 1–16 and fullscreen apps). This is what navigation
    /// uses; hidden slots of apps out of fullscreen are skipped.
    func navigableRows() -> [[String]] {
        let reachable = Set(desktops.desktops
            .filter { SymbolicHotKeys.switchableDesktops.contains($0.number) }
            .map(\.key) + desktops.fullscreens.map(\.key))
        return layout.rows.map { $0.filter(reachable.contains) }
    }

    private func reconcile() {
        let keys = desktops.orderedKeys
        // An empty list is a transient window-server state (sleep/wake,
        // display changes) — never let it wipe the user's arrangement.
        guard !keys.isEmpty else { return }
        let reconciled = arranged(Self.reconcile(layout, with: keys))
        guard reconciled != layout else { return }
        log.debug("Layout reconciled with \(keys.count, privacy: .public) spaces")
        layout = reconciled
        save()
    }

    /// Fullscreen apps keep their slot while out of fullscreen, and new ones
    /// appear next to the space they were made from.
    private static func reconcile(_ layout: GridLayout, with keys: [String]) -> GridLayout {
        layout.reconciled(with: keys,
                          retaining: FullscreenSpace.isKey,
                          besideNeighbor: FullscreenSpace.isKey)
    }

    /// The layout with native ordering applied, when that's turned on.
    /// Order = position in Mission Control's strip; hidden fullscreen slots
    /// (no position right now) keep their place at the end of their row.
    private func arranged(_ layout: GridLayout) -> GridLayout {
        guard prefs.rowsFollowNativeOrder else { return layout }
        let positions = Dictionary(desktops.orderedKeys.enumerated().map { ($0.element, $0.offset) },
                                   uniquingKeysWith: { first, _ in first })
        return layout.sortedWithinRows { positions[$0] }
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(layout), forKey: Self.storageKey)
        } catch {
            log.error("Saving layout failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
