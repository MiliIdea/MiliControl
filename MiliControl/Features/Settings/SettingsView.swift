//
//  SettingsView.swift
//  MiliControl
//

import SwiftUI

struct SettingsActions {
    let recheck: () -> Void
    let perform: (SetupItem.Fix) -> Void
    let openEditor: () -> Void
    /// Copies a plain-text report of what MiliControl reads from macOS.
    let copyDiagnostics: () -> Void
}

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var setup: SetupChecker
    @ObservedObject var desktops: DesktopStore
    @ObservedObject var updates: UpdateController
    let dockAvailable: Bool
    let actions: SettingsActions

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginMessage: String?
    @State private var diagnosticsCopied = false
    /// Live trackpad state for the swipe test (a shared singleton).
    @ObservedObject private var trackpad = TrackpadSwipes.shared

    var body: some View {
        Form {
            Section {
                ForEach(setup.items) { item in
                    SetupRow(item: item) { actions.perform(item.fix) }
                }
                HStack {
                    Button(diagnosticsCopied ? "Copied ✓" : "Copy Diagnostics") {
                        actions.copyDiagnostics()
                        diagnosticsCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { diagnosticsCopied = false }
                    }
                    .help("Copies what MiliControl reads from your macOS settings — paste it when reporting a problem.")
                    Spacer()
                    Button("Check Again") { actions.recheck() }
                }
            } header: {
                Text("Setup")
            } footer: {
                Text("MiliControl switches desktops with macOS's own “Switch to Desktop N” shortcuts, so every move is a native slide.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !setup.extraDesktops.isEmpty {
                Section {
                    ForEach(setup.extraDesktops) { extra in
                        ExtraDesktopRow(extra: extra,
                                        title: desktops.title(forKey: extra.key) ?? "Empty") {
                            actions.perform(.openKeyboardShortcuts)
                        }
                    }
                } header: {
                    Text("Desktops 10–16")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("macOS only gives Desktops 1–9 a switch shortcut. Without one, MiliControl still gets there — in a few slides. To make it one instant slide:")
                        Text("1. Click “Assign…” to open Keyboard Shortcuts ▸ Mission Control.")
                        Text("2. Double-click the empty key next to “Switch to Desktop 10”.")
                        Text("3. Press an unused combo, e.g. ⌃⌥⌘1 for 10, ⌃⌥⌘2 for 11…")
                        Text("Come back here — the list updates by itself.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Navigation") {
                Toggle("Wrap around within a row", isOn: $prefs.rules.wrapHorizontally)
                Toggle("Wrap from the last row to the first", isOn: $prefs.rules.wrapVertically)
                Picker("Moving up or down lands on", selection: $prefs.rules.verticalLanding) {
                    Text("First desktop of the row").tag(VerticalLanding.firstOfRow)
                    Text("Same column").tag(VerticalLanding.sameColumn)
                }
                Toggle("Hold an arrow to show the grid", isOn: $prefs.showHUD)
                    .help("Tap ⌃⌥ + arrow to switch instantly. Hold the arrow for 0.3 s to show the grid, tap arrows to choose, release ⌃⌥ to go.")
                Toggle("Four-finger swipes move through the grid", isOn: $prefs.fourFingerSwipes)
                    .help("Swipe left/right to move within a row, up/down to change rows — one desktop per swipe.")
                if prefs.fourFingerSwipes {
                    TrackpadTestRow(trackpad: trackpad)
                    Text("Turn off macOS's own four-finger gestures (Trackpad ▸ More Gestures ▸ “Swipe between full-screen applications” and Mission Control), or set them to three fingers — otherwise both move at once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Show desktop previews", isOn: $prefs.showPreviews)
                if prefs.showPreviews {
                    Text("Each desktop shows how it looked when you were last on it (macOS doesn't let apps see other desktops live). Needs Screen Recording. Previews stay in memory and are never saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Show the Dock only on chosen desktops", isOn: $prefs.manageDock)
                    .disabled(!dockAvailable)
                if prefs.manageDock {
                    ForEach(desktops.desktops) { desktop in
                        Toggle(isOn: dockBinding(for: desktop.key)) {
                            HStack(spacing: 8) {
                                Text("Desktop \(desktop.number)")
                                Text(desktops.title(forKey: desktop.key) ?? "Empty")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Dock")
            } footer: {
                Text(dockAvailable
                     ? "On the other desktops the Dock auto-hides — move the pointer to the bottom edge to reveal it. Your own Dock setting comes back when you turn this off or quit MiliControl."
                     : "Controlling the Dock isn't available on this version of macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                LabeledContent("Navigate the grid", value: "⌃⌥ ←  →  ↑  ↓")
                Picker("Open the grid editor", selection: $prefs.gridShortcut) {
                    ForEach(GridShortcut.allCases) { shortcut in
                        Text(shortcut.label).tag(shortcut)
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { wanted in
                        let error = LoginItem.setEnabled(wanted)
                        launchAtLogin = LoginItem.isEnabled
                        if let error = error {
                            loginMessage = error
                        } else if wanted && !launchAtLogin {
                            loginMessage = "Approve MiliControl in System Settings ▸ General ▸ Login Items."
                        } else {
                            loginMessage = nil
                        }
                    }))
                if let message = loginMessage {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
                Button("Edit Grid Layout…") { actions.openEditor() }
            }

            UpdatesSection(updates: updates, version: Self.version)
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 680)
    }

    private func dockBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { prefs.dockDesktopKeys.contains(key) },
            set: { visible in
                if visible { prefs.dockDesktopKeys.insert(key) } else { prefs.dockDesktopKeys.remove(key) }
            })
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

/// Version, update preferences, and "Check for Updates…".
private struct UpdatesSection: View {
    @ObservedObject var updates: UpdateController
    let version: String

    var body: some View {
        Section {
            LabeledContent("Version", value: version)
            if updates.isConfigured {
                if let available = updates.availableVersion {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 18)
                        Text("MiliControl \(available) is available")
                            .font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 8)
                        Button("Update…") { updates.checkForUpdates() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
                Toggle("Check for updates automatically", isOn: $updates.automaticallyChecks)
                Toggle("Download and install updates automatically", isOn: $updates.automaticallyDownloads)
                    .disabled(!updates.automaticallyChecks)
                HStack {
                    Text(lastCheckText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check for Updates…") { updates.checkForUpdates() }
                        .disabled(!updates.canCheckForUpdates)
                }
            }
        } header: {
            Text("Updates")
        } footer: {
            if !updates.isConfigured {
                Text("Updates aren't set up in this build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if updates.automaticallyDownloads && updates.automaticallyChecks {
                Text("Updates download in the background and install the next time MiliControl quits. Your permissions carry over.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lastCheckText: String {
        guard let date = updates.lastCheck else { return "Never checked" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last checked " + formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Live check that trackpad touches reach MiliControl: put fingers on the
/// trackpad and watch the count; swipe with four and see the arrow.
private struct TrackpadTestRow: View {
    @ObservedObject var trackpad: TrackpadSwipes

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("Trackpad test").font(.system(size: 13, weight: .medium))
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if trackpad.receivedTouches {
                Text("\(trackpad.fingerCount) finger\(trackpad.fingerCount == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                if let swipe = trackpad.lastSwipe {
                    Text(arrow(swipe))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var status: String {
        if !trackpad.isRunning { return "Not listening yet — toggle swipes off and on." }
        if trackpad.deviceCount == 0 { return "No trackpad found." }
        if !trackpad.receivedTouches {
            return "Touch the trackpad now. If nothing appears here, macOS isn't sharing touches — check Input Monitoring above, then quit and reopen MiliControl."
        }
        return "Touches are arriving. Swipe with four fingers — the last swipe shows on the right."
    }

    private var symbol: String {
        trackpad.receivedTouches ? "hand.point.up.left.fill" : "hand.raised.slash"
    }

    private var color: Color {
        trackpad.receivedTouches ? .green : .orange
    }

    private func arrow(_ direction: NavDirection) -> String {
        switch direction {
        case .left: return "←"
        case .right: return "→"
        case .up: return "↑"
        case .down: return "↓"
        }
    }
}

/// One desktop numbered 10–16: its shortcut, or a way to assign one.
private struct ExtraDesktopRow: View {
    let extra: ExtraDesktopShortcut
    let title: String
    let assign: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: extra.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(extra.isReady ? Color.green : Color.orange)
                .frame(width: 18)
            Text("Desktop \(extra.number)")
                .font(.system(size: 13, weight: .medium))
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if extra.isReady, let combo = extra.comboLabel {
                Text(combo)
                    .font(.system(size: 12, weight: .semibold).monospaced())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
            } else {
                Text(extra.isTurnedOff ? "Turned off" : "No shortcut")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Button(extra.isTurnedOff ? "Turn On…" : "Assign…", action: assign)
            }
        }
        .padding(.vertical, 1)
    }
}

private struct SetupRow: View {
    let item: SetupItem
    let fix: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.system(size: 15))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 13, weight: .medium))
                Text(item.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if item.status != .ok, let title = fixTitle {
                Button(title, action: fix)
            }
        }
        .padding(.vertical, 2)
    }

    private var symbol: String {
        switch item.status {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .problem: return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch item.status {
        case .ok: return .green
        case .warning: return .yellow
        case .problem: return .red
        }
    }

    private var fixTitle: String? {
        switch item.fix {
        case .requestAccessibility, .requestInputMonitoring: return "Grant Access…"
        case .openAccessibilitySettings, .openKeyboardShortcuts, .openDesktopAndDock,
             .openScreenRecordingSettings, .openTrackpadSettings: return "Open Settings"
        case .noAction: return nil
        }
    }
}
