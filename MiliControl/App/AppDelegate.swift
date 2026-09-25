//
//  AppDelegate.swift
//  MiliControl
//
//  Composition root: builds every component once and wires them together.
//
//      Hotkeys ──▶ NavigationCoordinator ──▶ Navigator (rules)
//                        │                   └▶ DesktopSwitcher (⌃N)
//                        ├▶ HUD
//                        └▶ GridEditor (when open, gets the arrows)
//      DesktopStore ──▶ LayoutStore (reconcile) ──▶ editor / navigation
//      SetupChecker ──▶ Settings window + menu-bar warning
//      UpdateController (Sparkle) ──▶ Settings "Updates" + menu-bar badge
//

import AppKit
import ApplicationServices
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let prefs = Preferences()
    private let desktops = DesktopStore()
    private let hotKeys = HotKeyCenter()
    private let switcher = DesktopSwitcher()
    private let hud = HUDController()
    private let setup = SetupChecker()
    private let updates = UpdateController()

    // Explicit types on every lazy component: these reference each other
    // (e.g. snapshots ↔ editor), and without annotations Swift's type
    // inference reports a circular reference.

    private lazy var layout: LayoutStore = LayoutStore(desktops: desktops, prefs: prefs)

    private lazy var dock: DockCoordinator = DockCoordinator(desktops: desktops, prefs: prefs, dock: DockController())

    private lazy var snapshots: DesktopSnapshots = DesktopSnapshots(
        desktops: desktops, prefs: prefs,
        overlaysVisible: { [weak self] in
            guard let self = self else { return false }
            return self.hud.isVisible || self.editor.isVisible
        })

    private lazy var dashboard: DashboardStore = DashboardStore(prefs: prefs)

    private lazy var navigation: NavigationCoordinator = NavigationCoordinator(
        desktops: desktops, layout: layout, prefs: prefs, switcher: switcher, hud: hud,
        snapshots: snapshots)

    private lazy var editor: GridEditorController = GridEditorController(
        desktops: desktops, layout: layout, prefs: prefs, navigation: navigation,
        snapshots: snapshots, dashboard: dashboard, webTabs: webTabs)

    private lazy var webTabs: WebTabsStore = WebTabsStore(prefs: prefs)

    private lazy var settings: SettingsWindowController = SettingsWindowController(
        prefs: prefs, setup: setup, desktops: desktops, updates: updates, dashboard: dashboard,
        dockAvailable: dock.isAvailable,
        actions: SettingsActions(
            recheck: { [weak self] in self?.runSetupCheck() },
            perform: { [weak self] fix in
                self?.setup.perform(fix)
                // Give System Settings a moment, then refresh the checklist.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.runSetupCheck() }
            },
            openEditor: { [weak self] in self?.editor.show() },
            copyDiagnostics: { [weak self] in
                guard let self = self else { return }
                let report = self.setup.diagnostics(desktops: self.desktops.desktops)
                    + "\n\n" + self.messages.diagnostics
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report, forType: .string)
            }))

    private let nowPlaying = NowPlaying()
    private let messages = MessageMonitor()

    private lazy var notch: NotchController = NotchController(
        nowPlaying: nowPlaying, prefs: prefs, messages: messages,
        openApp: { [weak self] app in
            // From the notch over the grid editor: close the editor, then go.
            if self?.editor.isVisible == true {
                self?.editor.hide()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { app.open() }
            } else {
                app.open()
            }
        })

    private let swipes = TrackpadSwipes.shared
    private var wakeObserver: NSObjectProtocol?

    private lazy var statusBar: StatusBarController = StatusBarController(
        prefs: prefs, setup: setup, updates: updates,
        actions: StatusBarController.Actions(
            openEditor: { [weak self] in self?.editor.show() },
            openSettings: { [weak self] in self?.settings.show() },
            recheck: { [weak self] in self?.runSetupCheck() }))

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu-bar utility, no Dock icon
        AppFonts.registerBundled()

        navigation.editorRouter = { [weak self] direction in
            self?.editor.moveSelection(direction) ?? false
        }
        navigation.onSetupProblem = { [weak self] in self?.runSetupCheck() }
        editor.onOpenSettings = { [weak self] in self?.settings.show() }
        editor.onVisibilityChange = { [weak self] visible in self?.notch.editorVisible = visible }

        registerHotKeys()
        statusBar.install()
        dock.start()
        snapshots.start()
        notch.start()

        // Unread messages (Telegram, WhatsApp, Slack) for the notch and dashboard.
        prefs.$messagesEnabled
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if enabled { self?.messages.start() } else { self?.messages.stop() }
            }
            .store(in: &cancellables)

        prefs.$showPreviews
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.runSetupCheck() }
            .store(in: &cancellables)

        // Four-finger swipes: one grid step per swipe.
        swipes.onSwipe = { [weak self] direction in self?.navigation.swipe(direction) }
        prefs.$fourFingerSwipes
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled {
                    // macOS may only share trackpad touches with Input Monitoring.
                    if !TrackpadSwipes.hasInputMonitoring { TrackpadSwipes.requestInputMonitoring() }
                    self.swipes.startListening()
                } else {
                    self.swipes.stopListening()
                }
                self.runSetupCheck()
            }
            .store(in: &cancellables)
        // Trackpads can reconnect after sleep; attach to them again.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.swipes.restart()
            }

        prefs.$gridShortcut
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.registerHotKeys() }
            .store(in: &cancellables)

        desktops.$desktops
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.runSetupCheck()
                self?.announceDesktopsNeedingShortcuts()
            }
            .store(in: &cancellables)

        desktops.$fullscreens
            .map(\.isEmpty)
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.runSetupCheck() }
            .store(in: &cancellables)

        runSetupCheck()
        announceDesktopsNeedingShortcuts()

        if !prefs.hasCompletedOnboarding {
            // First launch: macOS's own prompt adds MiliControl to the
            // Accessibility list so the user only has to flip the switch.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            prefs.hasCompletedOnboarding = true
            settings.show()
        } else if setup.hasProblems {
            settings.show()
        }
    }

    /// Put the user's own Dock setting back when MiliControl quits.
    func applicationWillTerminate(_ notification: Notification) {
        dock.restore()
        swipes.stopListening()
    }

    /// Double-clicking the app while it's running opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return true
    }

    // MARK: - Wiring

    private func registerHotKeys() {
        hotKeys.unregisterAll()

        let arrows: [(UInt32, NavDirection, String)] = [
            (HotKeySpec.arrowLeft, .left, "⌃⌥←"),
            (HotKeySpec.arrowRight, .right, "⌃⌥→"),
            (HotKeySpec.arrowUp, .up, "⌃⌥↑"),
            (HotKeySpec.arrowDown, .down, "⌃⌥↓"),
        ]
        for (keyCode, direction, name) in arrows {
            // Press and release are both needed: a quick tap switches, a long
            // press (arrow held ≥ 0.3 s) opens the grid HUD.
            hotKeys.register(HotKeySpec(keyCode: keyCode, modifiers: HotKeySpec.controlOption, name: name),
                             onRelease: { [weak self] in self?.navigation.arrowReleased(direction) },
                             action: { [weak self] in self?.navigation.arrowPressed(direction) })
        }
        hotKeys.register(prefs.gridShortcut.spec) { [weak self] in self?.editor.toggle() }

        runSetupCheck()
    }

    /// When a desktop numbered 10–16 appears without a shortcut, say so once
    /// (per desktop, ever): it already works, and here's how to make it instant.
    private func announceDesktopsNeedingShortcuts() {
        let storageKey = "announcedExtraDesktops"
        // Only claim "already reachable" when stepping actually works; if it
        // doesn't, the setup checklist flags it as a problem instead.
        let shortcuts = SymbolicHotKeys.read()
        guard SymbolicHotKeys.moveSpaceCombo(left: true, in: shortcuts) != nil,
              SymbolicHotKeys.moveSpaceCombo(left: false, in: shortcuts) != nil else { return }
        var announced = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
        let fresh = setup.extraDesktops.filter { !$0.isReady && !announced.contains($0.key) }
        guard let first = fresh.first else { return }
        fresh.forEach { announced.insert($0.key) }
        UserDefaults.standard.set(Array(announced), forKey: storageKey)

        let numbers: String = fresh.map { String($0.number) }.joined(separator: ", ")
        let which: String = fresh.count == 1 ? "Desktop \(first.number) is" : "Desktops \(numbers) are"
        let pronoun: String = fresh.count == 1 ? "it" : "each"
        hud.flash("\(which) in your grid and already reachable. For one instant slide, give \(pronoun) a shortcut: MiliControl Settings ▸ Desktops 10–16.",
                  duration: 6)
    }

    private func runSetupCheck() {
        setup.run(SetupChecker.Context(desktops: desktops.desktops,
                                       fullscreenCount: desktops.fullscreens.count,
                                       gridShortcut: prefs.gridShortcut,
                                       hotKeyFailures: hotKeys.failures,
                                       previewsEnabled: prefs.showPreviews,
                                       swipesEnabled: prefs.fourFingerSwipes,
                                       swipesAvailable: swipes.isAvailable,
                                       trackpadCount: swipes.deviceCount))
    }
}
