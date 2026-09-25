//
//  SetupChecker.swift
//  MiliControl
//
//  Verifies the handful of macOS settings MiliControl depends on and explains
//  how to fix each one. Everything is read-only; fixes open the right pane of
//  System Settings for the user to change.
//

import AppKit
import ApplicationServices

struct SetupItem: Identifiable, Equatable {
    enum Status: Int, Comparable {
        case ok, warning, problem
        static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }
    }

    enum Fix: Equatable {
        case requestAccessibility
        case openAccessibilitySettings
        case openKeyboardShortcuts
        case openDesktopAndDock
        case openScreenRecordingSettings
        case openTrackpadSettings
        case requestInputMonitoring
        case noAction
    }

    let id: String
    let title: String
    let detail: String
    let status: Status
    let fix: Fix
}

/// Shortcut status of one desktop numbered 10–16 (shown in Settings).
struct ExtraDesktopShortcut: Identifiable, Equatable {
    let number: Int
    let key: String
    /// e.g. "⌃⌥⌘1", or nil when no key is assigned.
    let comboLabel: String?
    /// A key is assigned but the shortcut is unchecked.
    let isTurnedOff: Bool
    var id: Int { number }
    var isReady: Bool { comboLabel != nil && !isTurnedOff }
}

final class SetupChecker: ObservableObject {

    @Published private(set) var items: [SetupItem] = []
    /// Desktops 10–16 that exist right now, with their shortcut status.
    @Published private(set) var extraDesktops: [ExtraDesktopShortcut] = []

    var worstStatus: SetupItem.Status { items.map(\.status).max() ?? .ok }
    var hasProblems: Bool { worstStatus == .problem }

    struct Context {
        var desktops: [Desktop]
        /// Fullscreen apps currently in the grid.
        var fullscreenCount: Int = 0
        var gridShortcut: GridShortcut
        var hotKeyFailures: [String]
        var previewsEnabled: Bool
        var swipesEnabled: Bool
        var swipesAvailable: Bool
        var trackpadCount: Int
    }

    func run(_ context: Context) {
        SystemPreferences.invalidate()                  // always check live values
        let shortcuts = SymbolicHotKeys.read()
        let shortcutsReadable = SymbolicHotKeys.isReadable
        var list: [SetupItem] = []

        // 1. Accessibility — needed to send the switch shortcut.
        if AXIsProcessTrusted() {
            list.append(.init(id: "ax", title: "Accessibility access",
                              detail: "Granted.", status: .ok, fix: .noAction))
        } else {
            list.append(.init(id: "ax", title: "Accessibility access",
                              detail: "Required to switch desktops. Enable MiliControl in Privacy & Security ▸ Accessibility, then quit and reopen MiliControl.",
                              status: .problem, fix: .requestAccessibility))
        }

        // 1b. If macOS's shortcut table can't be read, say so once — and don't
        //     claim any shortcut is on or off, because we don't know.
        if !shortcutsReadable {
            list.append(.init(id: "shortcuts-unreadable", title: "Keyboard Shortcuts settings",
                              detail: "MiliControl couldn't read your Keyboard Shortcuts settings, so it can't confirm them. Switching still uses the standard shortcuts — if it works, you can ignore this. Otherwise use Copy Diagnostics below.",
                              status: .warning, fix: .noAction))
        }

        // 2. "Switch to Desktop 1–9" — these have default keys, just enable them.
        let standard = shortcutsReadable
            ? context.desktops.filter { SymbolicHotKeys.defaultShortcutDesktops.contains($0.number) }
            : []
        var disabled: [Int] = []
        var unconfirmed: [Int] = []
        for desktop in standard {
            switch SymbolicHotKeys.switchShortcut(forDesktop: desktop.number, in: shortcuts) {
            case .disabled?: disabled.append(desktop.number)
            case .unconfirmed?: unconfirmed.append(desktop.number)
            default: break
            }
        }
        let canStep = SymbolicHotKeys.moveSpaceCombo(left: true, in: shortcuts) != nil
            && SymbolicHotKeys.moveSpaceCombo(left: false, in: shortcuts) != nil
        if !disabled.isEmpty {
            // Still reachable by stepping (just slower) → recommended, not broken.
            list.append(.init(id: "switch", title: "Switch to Desktop shortcuts",
                              detail: "Turn on “Switch to Desktop \(Self.list(disabled))” in Keyboard Shortcuts ▸ Mission Control. Until then \(disabled.count == 1 ? "that desktop takes" : "those desktops take") several slides.",
                              status: canStep ? .warning : .problem, fix: .openKeyboardShortcuts))
        } else if !unconfirmed.isEmpty {
            list.append(.init(id: "switch", title: "Switch to Desktop shortcuts",
                              detail: "Couldn't confirm “Switch to Desktop \(Self.list(unconfirmed))”. Make sure \(unconfirmed.count == 1 ? "it's" : "they're") checked in Keyboard Shortcuts ▸ Mission Control.",
                              status: .warning, fix: .openKeyboardShortcuts))
        } else if !standard.isEmpty {
            list.append(.init(id: "switch", title: "Switch to Desktop shortcuts",
                              detail: standard.count == 1 ? "Enabled." : "Enabled for all \(standard.count) desktops.",
                              status: .ok, fix: .noAction))
        }

        // 3. Desktops 10–16 — macOS lists them but assigns no key.
        let extras = context.desktops
            .filter { $0.number > SymbolicHotKeys.defaultShortcutDesktops.upperBound
                   && SymbolicHotKeys.switchableDesktops.contains($0.number) }
            .map { desktop -> ExtraDesktopShortcut in
                let entry = shortcuts[SymbolicHotKeys.ID.switchToDesktop(desktop.number)]
                return ExtraDesktopShortcut(number: desktop.number,
                                            key: desktop.key,
                                            comboLabel: entry?.combo.map(SymbolicHotKeys.label(for:)),
                                            isTurnedOff: entry?.combo != nil && entry?.enabled == false)
            }
        if extras != extraDesktops { extraDesktops = extras }
        let missing = shortcutsReadable ? extras.filter { !$0.isReady }.map(\.number) : []
        if !missing.isEmpty {
            list.append(.init(id: "extra", title: "Shortcuts for Desktops 10–16",
                              detail: "\(missing.count == 1 ? "Desktop" : "Desktops") \(Self.list(missing)) can be reached, but in several slides. For one instant slide, give \(missing.count == 1 ? "it" : "each") its own shortcut — see “Desktops 10–16” below.",
                              status: .warning, fix: .openKeyboardShortcuts))
        } else if shortcutsReadable, let last = extras.last {
            list.append(.init(id: "extra", title: "Shortcuts for Desktops 10–\(last.number)",
                              detail: "All assigned.", status: .ok, fix: .noAction))
        }

        // 3b. Desktops without a direct shortcut need "Move left/right a space".
        let needsStepping = !disabled.isEmpty || !missing.isEmpty
        if shortcutsReadable && needsStepping && !canStep {
            list.append(.init(id: "move", title: "Move left/right a space",
                              detail: "Some desktops have no direct shortcut, and “Move left a space” / “Move right a space” are off, so MiliControl can't reach them. Turn those on in Keyboard Shortcuts ▸ Mission Control.",
                              status: .problem, fix: .openKeyboardShortcuts))
        }

        // 3c. Beyond what macOS can switch to at all.
        let beyond = context.desktops.filter { !SymbolicHotKeys.switchableDesktops.contains($0.number) }
        if !beyond.isEmpty {
            list.append(.init(id: "limit", title: "More than 16 desktops",
                              detail: "macOS can only switch to Desktops 1–16, so \(beyond.count) desktop(s) are skipped when navigating.",
                              status: .warning, fix: .noAction))
        }

        // 3d. Fullscreen apps are reached by bringing them forward, which only
        //     slides to their space with this macOS setting on.
        if context.fullscreenCount > 0 {
            if Self.switchesSpaceOnActivate() {
                list.append(.init(id: "fullscreen", title: "Fullscreen apps",
                                  detail: "Switching to an app moves to its Space, so fullscreen apps are one slide away.",
                                  status: .ok, fix: .noAction))
            } else {
                list.append(.init(id: "fullscreen", title: "Fullscreen apps",
                                  detail: "Turn on “When switching to an application, switch to a Space with open windows for the application” (Desktop & Dock ▸ Mission Control). Until then fullscreen apps take a few slides.",
                                  status: .warning, fix: .openDesktopAndDock))
            }
        }

        // 4. Automatic rearranging only changes the number badges now (MiliControl
        //    re-reads the order before every switch), so it's a recommendation.
        switch Self.dockRearrangesSpaces() {
        case true?:
            list.append(.init(id: "mru", title: "Automatically rearrange Spaces",
                              detail: "Recommended off (Desktop & Dock ▸ Mission Control). When on, macOS keeps renumbering your desktops by recent use.",
                              status: .warning, fix: .openDesktopAndDock))
        case false?:
            list.append(.init(id: "mru", title: "Automatically rearrange Spaces",
                              detail: "Off.", status: .ok, fix: .noAction))
        case nil:
            break                                        // couldn't read — don't guess
        }

        // 5. ⌃↑ grid shortcut vs. macOS's own Mission Control shortcut.
        if shortcutsReadable, context.gridShortcut == .controlUp,
           SymbolicHotKeys.missionControlUsesControlUp(in: shortcuts) {
            list.append(.init(id: "mc", title: "Mission Control shortcut",
                              detail: "macOS still uses ⌃↑ for Mission Control. Uncheck “Mission Control” in Keyboard Shortcuts ▸ Mission Control, or pick ⌃⌥Space for the grid in MiliControl's settings.",
                              status: .problem, fix: .openKeyboardShortcuts))
        }

        // 5b. ⌃↓ closes the grid editor — unless macOS still owns it.
        if shortcutsReadable,
           SymbolicHotKeys.applicationWindowsUsesControlDown(in: shortcuts) {
            list.append(.init(id: "appwindows", title: "Close the grid editor with ⌃↓",
                              detail: "macOS still uses ⌃↓ for “Application windows”, so ⌃↓ can't close the grid editor. Uncheck “Application windows” in Keyboard Shortcuts ▸ Mission Control. (Esc and Done always work.)",
                              status: .warning, fix: .openKeyboardShortcuts))
        }

        // 6. Desktop previews need Screen Recording.
        if context.previewsEnabled && !ScreenCapture.hasPermission {
            list.append(.init(id: "screen", title: "Screen Recording (desktop previews)",
                              detail: "Allow MiliControl in Privacy & Security ▸ Screen & System Audio Recording, then quit and reopen MiliControl. Until then the grid shows app icons.",
                              status: .warning, fix: .openScreenRecordingSettings))
        }

        // 6b. Four-finger swipes.
        if context.swipesEnabled {
            if !context.swipesAvailable {
                list.append(.init(id: "swipes", title: "Four-finger swipes",
                                  detail: "This version of macOS doesn't let MiliControl read the trackpad, so swipes are unavailable. Keyboard navigation still works.",
                                  status: .warning, fix: .noAction))
            } else if !TrackpadSwipes.hasInputMonitoring {
                list.append(.init(id: "swipes", title: "Four-finger swipes: Input Monitoring",
                                  detail: "macOS only shares trackpad touches with apps allowed in Privacy & Security ▸ Input Monitoring. Enable MiliControl there, then quit and reopen MiliControl.",
                                  status: .problem, fix: .requestInputMonitoring))
            } else if context.trackpadCount == 0 {
                list.append(.init(id: "swipes", title: "Four-finger swipes",
                                  detail: "No trackpad found. Connect one (or wake the Mac) and click Check Again.",
                                  status: .warning, fix: .noAction))
            } else {
                let conflicts = Self.conflictingTrackpadGestures()
                if !conflicts.isEmpty {
                    list.append(.init(id: "swipes", title: "Four-finger swipes",
                                      detail: "macOS still uses four fingers for \(conflicts.joined(separator: " and ")), so both would move at once. In Trackpad ▸ More Gestures, turn those off or switch them to three fingers.",
                                      status: .warning, fix: .openTrackpadSettings))
                } else {
                    list.append(.init(id: "swipes", title: "Four-finger swipes",
                                      detail: "Ready — use the trackpad test below to confirm touches arrive.",
                                      status: .ok, fix: .noAction))
                }
            }
        }

        // 7. Our own hotkeys.
        if !context.hotKeyFailures.isEmpty {
            list.append(.init(id: "hotkeys", title: "MiliControl shortcuts",
                              detail: "Another app is using: \(context.hotKeyFailures.joined(separator: ", ")).",
                              status: .problem, fix: .noAction))
        }

        // 8. Stable location keeps the Accessibility grant from being reset.
        if !Bundle.main.bundlePath.hasPrefix("/Applications") {
            list.append(.init(id: "location", title: "App location",
                              detail: "Run MiliControl from /Applications. Copies elsewhere (like Xcode's build folder) can lose Accessibility access after each rebuild.",
                              status: .warning, fix: .noAction))
        }

        if list != items { items = list }
    }

    func perform(_ fix: SetupItem.Fix) {
        switch fix {
        case .requestAccessibility:
            if !AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
                Self.open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }
        case .openAccessibilitySettings:
            Self.open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .openKeyboardShortcuts:
            Self.open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
                      fallback: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")
        case .openDesktopAndDock:
            Self.open("x-apple.systempreferences:com.apple.Desktop-Settings.extension",
                      fallback: "x-apple.systempreferences:com.apple.preference.dock")
        case .openScreenRecordingSettings:
            Self.open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .requestInputMonitoring:
            // Shows macOS's prompt the first time; afterwards open the pane.
            if !TrackpadSwipes.requestInputMonitoring() {
                Self.open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
            }
        case .openTrackpadSettings:
            Self.open("x-apple.systempreferences:com.apple.Trackpad-Settings.extension",
                      fallback: "x-apple.systempreferences:com.apple.preference.trackpad")
        case .noAction:
            break
        }
    }

    // MARK: - Diagnostics

    /// Plain-text report of exactly what MiliControl reads from macOS, for
    /// the "Copy Diagnostics" button.
    func diagnostics(desktops: [Desktop]) -> String {
        SystemPreferences.invalidate()
        let table = SymbolicHotKeys.read()
        func describe(_ id: Int) -> String {
            guard let entry = table[id] else { return "missing" }
            let combo = entry.combo.map(SymbolicHotKeys.label(for:)) ?? (entry.hasValue ? "no key" : "default")
            return "\(entry.enabled ? "on" : "off"), \(combo)"
        }
        var lines: [String] = []
        let info = Bundle.main.infoDictionary
        lines.append("MiliControl \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("App path: \(Bundle.main.bundlePath)")
        lines.append("Accessibility: \(AXIsProcessTrusted() ? "granted" : "not granted")")
        lines.append("Screen Recording: \(ScreenCapture.hasPermission ? "granted" : "not granted")")
        lines.append("Input Monitoring: \(TrackpadSwipes.hasInputMonitoring ? "granted" : "not granted")")
        let pad = TrackpadSwipes.shared
        lines.append("Trackpad: available=\(pad.isAvailable) listening=\(pad.isRunning) devices=\(pad.deviceCount) touchesReceived=\(pad.receivedTouches)")
        lines.append("")
        lines.append("symbolichotkeys read via: \(SystemPreferences.source(of: SymbolicHotKeys.domainName).rawValue), \(table.count) entries")
        lines.append("  32 Mission Control: \(describe(SymbolicHotKeys.ID.missionControl))")
        lines.append("  33 Application windows: \(describe(SymbolicHotKeys.ID.applicationWindows))")
        lines.append("  79 Move left a space: \(describe(SymbolicHotKeys.ID.moveLeftSpace))")
        lines.append("  81 Move right a space: \(describe(SymbolicHotKeys.ID.moveRightSpace))")
        for number in SymbolicHotKeys.switchableDesktops {
            let id = SymbolicHotKeys.ID.switchToDesktop(number)
            lines.append("  \(id) Switch to Desktop \(number): \(describe(id))")
        }
        lines.append("")
        lines.append("com.apple.dock read via: \(SystemPreferences.source(of: "com.apple.dock").rawValue)")
        lines.append("  mru-spaces: \(String(describing: SystemPreferences.value("mru-spaces", in: "com.apple.dock") ?? "missing"))")
        lines.append("  autohide: \(String(describing: SystemPreferences.value("autohide", in: "com.apple.dock") ?? "missing"))")
        for domain in Self.trackpadDomains {
            lines.append("\(domain) read via: \(SystemPreferences.source(of: domain).rawValue)")
            for key in ["TrackpadFourFingerHorizSwipeGesture", "TrackpadFourFingerVertSwipeGesture",
                        "TrackpadThreeFingerHorizSwipeGesture", "TrackpadThreeFingerVertSwipeGesture"] {
                lines.append("  \(key): \(String(describing: SystemPreferences.value(key, in: domain) ?? "missing"))")
            }
        }
        for key in ["com.apple.trackpad.fourFingerHorizSwipeGesture", "com.apple.trackpad.fourFingerVertSwipeGesture"] {
            lines.append("currentHost \(key): \(String(describing: SystemPreferences.currentHostGlobalValue(key) ?? "missing"))")
        }
        lines.append("")
        lines.append("Desktops: " + desktops.map { "\($0.number)" }.joined(separator: " "))
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// "When switching to an application, switch to a Space with open windows
    /// for the application" — a global setting (older macOS kept it in the
    /// Dock's domain). On unless explicitly turned off.
    private static func switchesSpaceOnActivate() -> Bool {
        if let global = UserDefaults.standard.object(forKey: "AppleSpacesSwitchOnActivate") as? Bool {
            return global
        }
        return (SystemPreferences.value("workspaces-auto-swoosh", in: "com.apple.dock") as? NSNumber)?.boolValue ?? true
    }

    /// nil when macOS's Dock settings couldn't be read.
    private static func dockRearrangesSpaces() -> Bool? {
        guard let dock = SystemPreferences.domain("com.apple.dock") else { return nil }
        return (dock["mru-spaces"] as? NSNumber)?.boolValue ?? true   // macOS default: on
    }

    /// Built-in and Bluetooth (Magic) trackpad settings.
    private static let trackpadDomains = ["com.apple.AppleMultitouchTrackpad",
                                          "com.apple.driver.AppleBluetoothMultitouch.trackpad"]

    /// Native gestures that also use four fingers ("2" = enabled in these
    /// domains). Unreadable domains are ignored rather than guessed.
    private static func conflictingTrackpadGestures() -> [String] {
        var horizontal = false
        var vertical = false
        for domain in trackpadDomains {
            guard let values = SystemPreferences.domain(domain) else { continue }
            if (values["TrackpadFourFingerHorizSwipeGesture"] as? NSNumber)?.intValue == 2 { horizontal = true }
            if (values["TrackpadFourFingerVertSwipeGesture"] as? NSNumber)?.intValue == 2 { vertical = true }
        }
        // Recent macOS also keeps the live values per host.
        if (SystemPreferences.currentHostGlobalValue("com.apple.trackpad.fourFingerHorizSwipeGesture") as? NSNumber)?.intValue == 2 {
            horizontal = true
        }
        if (SystemPreferences.currentHostGlobalValue("com.apple.trackpad.fourFingerVertSwipeGesture") as? NSNumber)?.intValue == 2 {
            vertical = true
        }
        // Mission Control / App Exposé can be switched off in the Dock itself.
        if vertical, let dock = SystemPreferences.domain("com.apple.dock") {
            let missionControlOn = (dock["showMissionControlGestureEnabled"] as? NSNumber)?.boolValue ?? true
            let appExposeOn = (dock["showAppExposeGestureEnabled"] as? NSNumber)?.boolValue ?? true
            vertical = missionControlOn || appExposeOn
        }
        var names: [String] = []
        if horizontal { names.append("“Swipe between full-screen applications”") }
        if vertical { names.append("Mission Control / App Exposé") }
        return names
    }

    private static func open(_ primary: String, fallback: String? = nil) {
        if let url = URL(string: primary), NSWorkspace.shared.open(url) { return }
        if let fallback = fallback, let url = URL(string: fallback) { _ = NSWorkspace.shared.open(url) }
    }

    private static func list(_ numbers: [Int]) -> String {
        numbers.map(String.init).joined(separator: ", ")
    }
}
