//
//  DockCoordinator.swift
//  MiliControl
//
//  "Show the Dock only on chosen desktops": on every desktop change, keeps the
//  Dock visible on the desktops you picked and auto-hidden everywhere else.
//
//  Your own Dock setting is saved the moment this is turned on and restored
//  when it's turned off or MiliControl quits (and on the next launch if
//  MiliControl ever quit unexpectedly).
//
//  (The grid editor hides the Dock separately, with a temporary full-screen
//  presentation mode that never touches this setting.)
//

import Foundation
import Combine

final class DockCoordinator {

    private let desktops: DesktopStore
    private let prefs: Preferences
    private let dock: DockController
    private var cancellables = Set<AnyCancellable>()

    private static let savedOriginalKey = "dock.originalAutohide"
    private let defaults = UserDefaults.standard

    var isAvailable: Bool { dock.isAvailable }

    init(desktops: DesktopStore, prefs: Preferences, dock: DockController) {
        self.desktops = desktops
        self.prefs = prefs
        self.dock = dock
    }

    func start() {
        // @Published fires before the value is stored; hop to the next run
        // loop turn so apply() reads the new values.
        desktops.$currentKey
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)

        prefs.$manageDock
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)

        prefs.$dockDesktopKeys
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)

        apply()
    }

    /// Puts the Dock back the way the user had it (called on quit).
    func restore() {
        guard let original = defaults.object(forKey: Self.savedOriginalKey) as? Bool else { return }
        dock.setAutoHide(original)
        defaults.removeObject(forKey: Self.savedOriginalKey)
    }

    private func apply() {
        guard prefs.manageDock else {
            restore()
            return
        }

        // Remember the user's own setting once, before we start changing it.
        if defaults.object(forKey: Self.savedOriginalKey) == nil {
            defaults.set(dock.isAutoHideEnabled, forKey: Self.savedOriginalKey)
        }

        // First time on: keep the Dock on Desktop 1 by default.
        if prefs.dockDesktopKeys.isEmpty,
           let first = desktops.desktops.first(where: { $0.number == 1 }) {
            prefs.dockDesktopKeys = [first.key]
            return   // the dockDesktopKeys subscription re-runs apply()
        }

        // On a fullscreen app (not a numbered desktop) leave the Dock alone.
        guard let current = desktops.currentKey else { return }
        dock.setAutoHide(!prefs.dockDesktopKeys.contains(current))
    }
}
