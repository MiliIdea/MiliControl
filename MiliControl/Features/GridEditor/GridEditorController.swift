//
//  GridEditorController.swift
//  MiliControl
//
//  The full-screen grid (⌃↑ by default): see every desktop in your rows,
//  drag tiles to arrange them, click one to go there.
//

import AppKit
import SwiftUI

final class GridEditorModel: ObservableObject {
    @Published var selectedKey: String?
    /// The web tab shown instead of the desktops (nil = desktops). Kept while
    /// the editor is closed, so you come back to the same page.
    @Published var selectedTab: UUID?
    @Published var draggingKey: String? {
        didSet { if draggingKey == nil { dragOriginRow = nil } }
    }
    /// The row the current drag started in.
    var dragOriginRow: Int?
    /// Desktop numbers without a direct switch shortcut (reached in several slides).
    @Published var slowDesktops: Set<Int> = []
    /// "The order inside a row follows Mission Control" — shown after trying
    /// to reorder within a row while native order is on.
    @Published private(set) var showsOrderHint = false
    private var hintGeneration = 0

    func showOrderHint() {
        hintGeneration += 1
        let generation = hintGeneration
        if !showsOrderHint {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showsOrderHint = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            guard let self = self, self.hintGeneration == generation else { return }
            self.hideOrderHint()
        }
    }

    func hideOrderHint() {
        guard showsOrderHint else { return }
        withAnimation(.easeOut(duration: 0.2)) { showsOrderHint = false }
    }
}

/// Borderless windows can't become key by default; the editor needs keys.
private final class EditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class GridEditorController {

    let model = GridEditorModel()

    private let desktops: DesktopStore
    private let layout: LayoutStore
    private let prefs: Preferences
    private let navigation: NavigationCoordinator
    private let snapshots: DesktopSnapshots
    private let dashboard: DashboardStore
    private let webTabs: WebTabsStore
    /// Opens MiliControl Settings.
    var onOpenSettings: (() -> Void)?
    /// Told when the editor opens (true) or closes (false).
    var onVisibilityChange: ((Bool) -> Void)?

    private var window: EditorWindow?
    private var keyMonitor: Any?
    /// The app's presentation options before the editor took over the screen.
    private var savedPresentationOptions: NSApplication.PresentationOptions?

    var isVisible: Bool { window != nil }

    init(desktops: DesktopStore, layout: LayoutStore, prefs: Preferences,
         navigation: NavigationCoordinator, snapshots: DesktopSnapshots, dashboard: DashboardStore,
         webTabs: WebTabsStore) {
        self.desktops = desktops
        self.layout = layout
        self.prefs = prefs
        self.navigation = navigation
        self.snapshots = snapshots
        self.dashboard = dashboard
        self.webTabs = webTabs
    }

    // MARK: - Show / hide

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard !isVisible else { return }
        desktops.refresh()
        desktops.refreshApps()
        snapshots.captureNow()          // current desktop's preview, taken before the editor covers it
        model.selectedKey = desktops.currentKey ?? layout.layout.allKeys.first
        model.draggingKey = nil
        let shortcuts = SymbolicHotKeys.read()
        model.slowDesktops = Set(desktops.desktops
            .filter { SymbolicHotKeys.usableSwitchCombo(forDesktop: $0.number, in: shortcuts) == nil }
            .map(\.number))
        if DashboardView.hasPanels(prefs) { dashboard.activate() }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let window = EditorWindow(contentRect: screen.frame,
                                  styleMask: [.borderless],
                                  backing: .buffered,
                                  defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Always dark, like Mission Control: the grid sits on a dimmed blur of
        // your desktop, and its cards, previews and dashboard are designed
        // for that. (Web tabs still follow your system appearance.)
        window.appearance = NSAppearance(named: .darkAqua)

        let root = GridEditorView(
            model: model,
            desktops: desktops,
            layout: layout,
            snapshots: snapshots,
            prefs: prefs,
            dashboard: dashboard,
            webTabs: webTabs,
            screenSize: screen.frame.size,
            actions: GridEditorActions(
                go: { [weak self] key in self?.go(to: key) },
                close: { [weak self] in self?.hide() },
                addRow: { [weak self] in self?.layout.update { $0.addRow() } },
                removeRow: { [weak self] index in self?.layout.update { $0.removeRow(at: index) } },
                reset: { [weak self] in self?.confirmReset() },
                openMissionControl: { [weak self] in self?.leave(toApp: "com.apple.exposelauncher") },
                openSettings: { [weak self] in
                    self?.hide()
                    self?.onOpenSettings?()
                }),
            dashboardActions: DashboardActions(
                openCalendar: { [weak self] in self?.leave(toApp: "com.apple.iCal") },
                requestAccess: { [weak self] type in
                    // macOS's prompt would open behind the editor: step aside,
                    // ask, and come back once access is granted.
                    self?.leave {
                        self?.dashboard.requestAccess(to: type) { granted in
                            if granted { self?.show() }
                        }
                    }
                },
                openPrivacySettings: { [weak self] type in
                    guard let url = DashboardStore.privacySettingsURL(for: type) else { return }
                    self?.leave { NSWorkspace.shared.open(url) }
                }))
        // NSHostingController (not a bare NSHostingView) owns sizing — avoids
        // AppKit layout-recursion warnings in borderless windows.
        window.contentViewController = NSHostingController(rootView: root.environment(\.colorScheme, .dark))
        window.setFrame(screen.frame, display: true)

        NSApp.activate(ignoringOtherApps: true)
        takeOverScreen()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        onVisibilityChange?(true)
        installKeyMonitor()
        // SwiftUI likes to focus the first text field (a row name) on open;
        // start with no focus so the arrow keys drive the grid. (A web tab
        // focuses its page itself.)
        if model.selectedTab == nil {
            DispatchQueue.main.async { [weak window] in window?.makeFirstResponder(nil) }
        }
    }

    func hide() {
        guard let window = window else { return }
        removeKeyMonitor()
        window.orderOut(nil)
        self.window = nil
        onVisibilityChange?(false)
        model.draggingKey = nil
        model.hideOrderHint()
        dashboard.deactivate()
        webTabs.show(nil)
        releaseScreen()
        // Hand keyboard focus back to the app you were in, unless another
        // MiliControl window (Settings) is still open.
        // (Panels — the HUD, the notch player — don't count.)
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeKey && !($0 is NSPanel) }) {
            NSApp.hide(nil)
            // Hiding also takes down the always-on panels (the notch player);
            // bring them back without taking focus from that app.
            DispatchQueue.main.async { NSApp.unhideWithoutActivation() }
        }
    }

    // MARK: - Full-screen presentation

    /// While the editor is open, macOS hides the Dock and menu bar entirely,
    /// like a fullscreen app — otherwise the Dock stays live underneath and
    /// reacts to the pointer (e.g. magnifying icons) behind the blur.
    /// This is a temporary display mode: the Dock's auto-hide setting and
    /// MiliControl's per-desktop Dock choices are never touched.
    private func takeOverScreen() {
        guard savedPresentationOptions == nil else { return }
        savedPresentationOptions = NSApp.presentationOptions
        // hideMenuBar requires hideDock — this pair is always valid.
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
    }

    private func releaseScreen() {
        guard let saved = savedPresentationOptions else { return }
        NSApp.presentationOptions = saved
        savedPresentationOptions = nil
    }

    /// Called by the navigation coordinator for ⌃⌥ + arrows while the editor
    /// is open: moves the selection instead of switching.
    func moveSelection(_ direction: NavDirection) -> Bool {
        guard isVisible else { return false }
        let rows = layout.navigableRows()
        if let target = Navigator.target(from: model.selectedKey, direction: direction,
                                         rows: rows, rules: prefs.rules) {
            model.selectedKey = target
        }
        return true
    }

    // MARK: - Actions

    private func go(to key: String) {
        hide()   // also hands focus back, so the destination's app activates normally
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.navigation.switchNow(to: key)
        }
    }

    /// Closes the editor, then does something outside it (the editor sits
    /// above everything, so apps and System Settings would open behind it).
    private func leave(then action: @escaping () -> Void) {
        hide()
        DispatchQueue.main.async(execute: action)
    }

    private func leave(toApp bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        leave { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) }
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset the grid layout?"
        alert.informativeText = "Your desktops go back to macOS's order, 4 per row."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        if let window = window {
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn { self?.layout.resetToDefault() }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            layout.resetToDefault()
        }
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
    }

    /// Returns true if the key was handled.
    private func handle(_ event: NSEvent) -> Bool {
        // Only an attached sheet (reset confirmation) should get keys then.
        if window?.attachedSheet != nil { return false }
        // A web tab gets every key (games, chat boxes…) except the ways out:
        // Esc and ⌃↓ close the editor.
        if model.selectedTab != nil, prefs.webTabs.contains(where: { $0.id == model.selectedTab }) {
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if event.keyCode == 53 && mods.isEmpty || event.keyCode == 125 && mods == .control {
                hide()
                return true
            }
            return false
        }
        // Typing (a row name or the sticky note): let the text have every key,
        // except Esc, which just finishes editing instead of closing the editor.
        if let editor = window?.firstResponder as? NSTextView, editor.isEditable {
            if event.keyCode == 53 {
                window?.makeFirstResponder(nil)
                return true
            }
            return false
        }
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let plain = mods.isEmpty
        let command = mods == .command
        let control = mods == .control

        switch event.keyCode {
        case 53 where plain:                             // Esc
            hide()
        case 125 where control:                          // ⌃↓ — the counterpart of ⌃↑
            hide()
        case 36 where plain, 76 where plain:             // Return / Enter
            if let key = model.selectedKey { go(to: key) }
        case 123 where plain: _ = moveSelection(.left)
        case 124 where plain: _ = moveSelection(.right)
        case 125 where plain: _ = moveSelection(.down)
        case 126 where plain: _ = moveSelection(.up)
        case 45 where command:                           // ⌘N
            layout.update { $0.addRow() }
        case 43 where command:                           // ⌘,
            hide()
            onOpenSettings?()
        default:
            return false
        }
        return true
    }
}
