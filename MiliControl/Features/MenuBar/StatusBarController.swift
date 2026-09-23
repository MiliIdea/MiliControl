//
//  StatusBarController.swift
//  MiliControl
//
//  The menu-bar item. Its icon turns into a warning when setup needs
//  attention, and into a download arrow when an update is waiting.
//

import AppKit
import Combine

final class StatusBarController: NSObject, NSMenuDelegate {

    struct Actions {
        let openEditor: () -> Void
        let openSettings: () -> Void
        let recheck: () -> Void
    }

    private let prefs: Preferences
    private let setup: SetupChecker
    private let updates: UpdateController
    private let actions: Actions
    private var item: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    init(prefs: Preferences, setup: SetupChecker, updates: UpdateController, actions: Actions) {
        self.prefs = prefs
        self.setup = setup
        self.updates = updates
        self.actions = actions
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.item = item
        updateIcon()

        setup.$items
            .combineLatest(updates.$availableVersion)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        // `@Published` fires before the value is stored; read it on the next pass.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let problems = self.setup.hasProblems
            let update = self.updates.availableVersion
            let name = problems ? "exclamationmark.triangle"
                : update != nil ? "arrow.down.circle" : "square.grid.3x2"
            let image = NSImage(systemSymbolName: name, accessibilityDescription: "MiliControl")
            image?.isTemplate = true
            self.item?.button?.image = image
            self.item?.button?.toolTip = problems ? "MiliControl — setup needs attention"
                : update.map { "MiliControl — version \($0) is available" } ?? "MiliControl"
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        actions.recheck()
        menu.removeAllItems()

        if let version = updates.availableVersion {
            let update = NSMenuItem(title: "Update to MiliControl \(version)…",
                                    action: #selector(checkForUpdates), keyEquivalent: "")
            update.target = self
            update.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            menu.addItem(update)
            menu.addItem(.separator())
        }

        let open = NSMenuItem(title: "Open Grid Editor  (\(prefs.gridShortcut.label))",
                              action: #selector(openEditor), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        if setup.worstStatus >= .warning {
            menu.addItem(.separator())
            let title = setup.hasProblems ? "⚠︎  Finish Setup…" : "Recommended Setup…"
            let fix = NSMenuItem(title: title, action: #selector(openSettings), keyEquivalent: "")
            fix.target = self
            menu.addItem(fix)
        }

        menu.addItem(.separator())
        let hint = NSMenuItem(title: "Navigate: ⌃⌥ + arrow keys", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        menu.addItem(.separator())
        if updates.isConfigured {
            let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            check.target = self
            check.isEnabled = updates.canCheckForUpdates
            menu.addItem(check)
        }
        let quit = NSMenuItem(title: "Quit MiliControl", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func openEditor() { actions.openEditor() }
    @objc private func openSettings() { actions.openSettings() }
    @objc private func checkForUpdates() { updates.checkForUpdates() }
    @objc private func quit() { NSApp.terminate(nil) }
}
