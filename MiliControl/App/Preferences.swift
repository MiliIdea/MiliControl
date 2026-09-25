//
//  Preferences.swift
//  MiliControl
//
//  User settings, persisted in UserDefaults.
//

import Foundation
import Combine

/// Which shortcut opens the grid editor.
enum GridShortcut: String, CaseIterable, Identifiable {
    /// ⌃↑ — replaces macOS's Mission Control shortcut (which must be turned off).
    case controlUp
    /// ⌃⌥Space — conflict-free alternative.
    case controlOptionSpace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .controlUp: return "⌃↑"
        case .controlOptionSpace: return "⌃⌥Space"
        }
    }

    var spec: HotKeySpec {
        switch self {
        case .controlUp:
            return HotKeySpec(keyCode: HotKeySpec.arrowUp, modifiers: HotKeySpec.control, name: "⌃↑")
        case .controlOptionSpace:
            return HotKeySpec(keyCode: HotKeySpec.space, modifiers: HotKeySpec.controlOption, name: "⌃⌥Space")
        }
    }
}

/// How the dashboard's clock is drawn.
enum ClockStyle: String, CaseIterable, Identifiable {
    case analog
    case digital

    var id: String { rawValue }
    var label: String { self == .analog ? "Analog" : "Digital" }
}

/// A second calendar shown beside the Gregorian date on the dashboard.
enum SecondaryCalendar: String, CaseIterable, Identifiable {
    case none
    case persian        // Solar Hijri (Shamsi)
    case islamic        // Hijri (Umm al-Qura)
    case hebrew
    case chinese
    case japanese
    case buddhist
    case indian

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .persian: return "Persian (Shamsi)"
        case .islamic: return "Islamic (Hijri)"
        case .hebrew: return "Hebrew"
        case .chinese: return "Chinese"
        case .japanese: return "Japanese"
        case .buddhist: return "Buddhist"
        case .indian: return "Indian National"
        }
    }

    var calendar: Calendar? {
        let identifier: Calendar.Identifier
        switch self {
        case .none: return nil
        case .persian: identifier = .persian
        case .islamic: identifier = .islamicUmmAlQura
        case .hebrew: identifier = .hebrew
        case .chinese: identifier = .chinese
        case .japanese: identifier = .japanese
        case .buddhist: identifier = .buddhist
        case .indian: identifier = .indian
        }
        return Calendar(identifier: identifier)
    }

    /// Dates are written in the calendar's own language and digits.
    var locale: Locale {
        switch self {
        case .none: return .current
        case .persian: return Locale(identifier: "fa_IR")
        case .islamic: return Locale(identifier: "ar_SA")
        case .hebrew: return Locale(identifier: "he_IL")
        case .chinese: return Locale(identifier: "zh_CN")
        case .japanese: return Locale(identifier: "ja_JP")
        case .buddhist: return Locale(identifier: "th_TH")
        case .indian: return Locale(identifier: "hi_IN")
        }
    }
}

final class Preferences: ObservableObject {

    private enum Key {
        static let rowsFollowNativeOrder = "grid.followNativeOrder"
        static let showDashboard = "dashboard.show"
        static let notchPlayer = "notch.player"
        static let messages = "messages.enabled"
        static let notchMessages = "messages.notchPeek"
        static let notchInbox = "messages.notchInbox"
        static let dashboardClock = "dashboard.clock"
        static let clockStyle = "dashboard.clockStyle"
        static let secondaryCalendar = "dashboard.secondaryCalendar"
        static let dashboardMonth = "dashboard.month"
        static let dashboardEvents = "dashboard.events"
        static let dashboardTodo = "dashboard.todo"
        static let webTabs = "web.tabs.v1"
        static let dashboardNote = "dashboard.note"
        static let noteText = "dashboard.noteText"
        static let rules = "navigation.rules.v1"
        static let gridShortcut = "gridShortcut"
        static let showHUD = "showHUD"
        static let showPreviews = "previews.show"
        static let fourFingerSwipes = "gestures.fourFinger"
        static let manageDock = "dock.manage"
        static let dockDesktopKeys = "dock.visibleDesktops"
        static let onboarded = "hasCompletedOnboarding"
    }

    private let defaults: UserDefaults

    @Published var rules: NavigationRules {
        didSet { if let data = try? JSONEncoder().encode(rules) { defaults.set(data, forKey: Key.rules) } }
    }

    @Published var gridShortcut: GridShortcut {
        didSet { defaults.set(gridShortcut.rawValue, forKey: Key.gridShortcut) }
    }

    /// Holding an arrow for 0.3 s shows the grid HUD (grid mode). When off,
    /// every press is a quick tap that switches immediately.
    @Published var showHUD: Bool {
        didSet { defaults.set(showHUD, forKey: Key.showHUD) }
    }

    /// Four-finger trackpad swipes navigate the grid (one step per swipe).
    @Published var fourFingerSwipes: Bool {
        didSet { defaults.set(fourFingerSwipes, forKey: Key.fourFingerSwipes) }
    }

    /// Show a snapshot of each desktop (as you last saw it) instead of app
    /// icons. Needs Screen Recording.
    @Published var showPreviews: Bool {
        didSet { defaults.set(showPreviews, forKey: Key.showPreviews) }
    }

    /// Show the Dock only on the desktops in `dockDesktopKeys`; auto-hide it
    /// on all others.
    @Published var manageDock: Bool {
        didSet { defaults.set(manageDock, forKey: Key.manageDock) }
    }

    /// Desktops (by layout key) where the Dock stays visible.
    @Published var dockDesktopKeys: Set<String> {
        didSet { defaults.set(Array(dockDesktopKeys), forKey: Key.dockDesktopKeys) }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboarded) }
    }

    /// Keep each row sorted by macOS's desktop number, so every move slides
    /// in the direction you pressed. Rows are still yours; the order inside
    /// a row is changed in Mission Control.
    @Published var rowsFollowNativeOrder: Bool {
        didSet { defaults.set(rowsFollowNativeOrder, forKey: Key.rowsFollowNativeOrder) }
    }

    // MARK: Notch player

    /// Show what Spotify / Music is playing around the notch.
    @Published var notchPlayer: Bool {
        didSet { defaults.set(notchPlayer, forKey: Key.notchPlayer) }
    }

    // MARK: Messages (Telegram, WhatsApp, Slack)

    /// Watch unread badges and message banners of the messaging apps.
    @Published var messagesEnabled: Bool {
        didSet { defaults.set(messagesEnabled, forKey: Key.messages) }
    }
    /// Briefly show each new message in the notch.
    @Published var notchMessages: Bool {
        didSet { defaults.set(notchMessages, forKey: Key.notchMessages) }
    }
    /// While the grid editor is open, show unread apps in the notch.
    @Published var notchInbox: Bool {
        didSet { defaults.set(notchInbox, forKey: Key.notchInbox) }
    }

    // MARK: Web tabs (sites inside the grid view)

    @Published var webTabs: [WebTab] {
        didSet { if let data = try? JSONEncoder().encode(webTabs) { defaults.set(data, forKey: Key.webTabs) } }
    }

    // MARK: Dashboard (the strip above the rows in the grid editor)

    @Published var showDashboard: Bool {
        didSet { defaults.set(showDashboard, forKey: Key.showDashboard) }
    }
    @Published var dashboardClock: Bool {
        didSet { defaults.set(dashboardClock, forKey: Key.dashboardClock) }
    }
    @Published var clockStyle: ClockStyle {
        didSet { defaults.set(clockStyle.rawValue, forKey: Key.clockStyle) }
    }
    /// A second calendar next to the date (clock) and month name (month).
    @Published var secondaryCalendar: SecondaryCalendar {
        didSet { defaults.set(secondaryCalendar.rawValue, forKey: Key.secondaryCalendar) }
    }
    @Published var dashboardMonth: Bool {
        didSet { defaults.set(dashboardMonth, forKey: Key.dashboardMonth) }
    }
    /// "Up Next" — today's and tomorrow's events from Calendar.
    @Published var dashboardEvents: Bool {
        didSet { defaults.set(dashboardEvents, forKey: Key.dashboardEvents) }
    }
    /// MiliControl's own to-do list.
    @Published var dashboardTodo: Bool {
        didSet { defaults.set(dashboardTodo, forKey: Key.dashboardTodo) }
    }
    /// The sticky note in the dashboard's top-right corner.
    @Published var dashboardNote: Bool {
        didSet { defaults.set(dashboardNote, forKey: Key.dashboardNote) }
    }
    @Published var noteText: String {
        didSet { defaults.set(noteText, forKey: Key.noteText) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.rules),
           let saved = try? JSONDecoder().decode(NavigationRules.self, from: data) {
            rules = saved
        } else {
            rules = NavigationRules()
        }
        gridShortcut = GridShortcut(rawValue: defaults.string(forKey: Key.gridShortcut) ?? "") ?? .controlUp
        showHUD = defaults.object(forKey: Key.showHUD) as? Bool ?? true
        showPreviews = defaults.bool(forKey: Key.showPreviews)
        fourFingerSwipes = defaults.bool(forKey: Key.fourFingerSwipes)
        manageDock = defaults.bool(forKey: Key.manageDock)
        dockDesktopKeys = Set(defaults.stringArray(forKey: Key.dockDesktopKeys) ?? [])
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarded)

        func flag(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        rowsFollowNativeOrder = flag(Key.rowsFollowNativeOrder)
        notchPlayer = flag(Key.notchPlayer)
        messagesEnabled = flag(Key.messages)
        notchMessages = flag(Key.notchMessages)
        notchInbox = flag(Key.notchInbox)
        showDashboard = flag(Key.showDashboard)
        dashboardClock = flag(Key.dashboardClock)
        clockStyle = ClockStyle(rawValue: defaults.string(forKey: Key.clockStyle) ?? "") ?? .analog
        secondaryCalendar = SecondaryCalendar(rawValue: defaults.string(forKey: Key.secondaryCalendar) ?? "") ?? .none
        dashboardMonth = flag(Key.dashboardMonth)
        dashboardEvents = flag(Key.dashboardEvents)
        dashboardTodo = flag(Key.dashboardTodo)
        webTabs = defaults.data(forKey: Key.webTabs)
            .flatMap { try? JSONDecoder().decode([WebTab].self, from: $0) } ?? WebTab.defaults
        dashboardNote = flag(Key.dashboardNote)
        noteText = defaults.string(forKey: Key.noteText) ?? ""
    }
}
