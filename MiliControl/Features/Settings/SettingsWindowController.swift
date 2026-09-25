//
//  SettingsWindowController.swift
//  MiliControl
//

import AppKit
import SwiftUI

final class SettingsWindowController {

    private let prefs: Preferences
    private let setup: SetupChecker
    private let desktops: DesktopStore
    private let updates: UpdateController
    private let dashboard: DashboardStore
    private let dockAvailable: Bool
    private let actions: SettingsActions
    private var window: NSWindow?
    private var keyObserver: NSObjectProtocol?

    init(prefs: Preferences, setup: SetupChecker, desktops: DesktopStore,
         updates: UpdateController, dashboard: DashboardStore,
         dockAvailable: Bool, actions: SettingsActions) {
        self.prefs = prefs
        self.setup = setup
        self.desktops = desktops
        self.updates = updates
        self.dashboard = dashboard
        self.dockAvailable = dockAvailable
        self.actions = actions
    }

    deinit {
        if let o = keyObserver { NotificationCenter.default.removeObserver(o) }
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        actions.recheck()
        desktops.refresh()
        desktops.refreshApps()      // desktop labels in the Dock section
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsView(prefs: prefs, setup: setup, desktops: desktops,
                                updates: updates, dashboard: dashboard,
                                dockAvailable: dockAvailable, actions: actions)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "MiliControl Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        // Remember where the user put the window; center it the first time.
        if !window.setFrameUsingName("MiliControlSettings") { window.center() }
        window.setFrameAutosaveName("MiliControlSettings")
        // Re-check whenever you come back, e.g. after flipping a switch in
        // System Settings.
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.actions.recheck()
                self?.dashboard.refreshAccess()
            }
        return window
    }
}
