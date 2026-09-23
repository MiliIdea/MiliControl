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

final class Preferences: ObservableObject {

    private enum Key {
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
    }
}
