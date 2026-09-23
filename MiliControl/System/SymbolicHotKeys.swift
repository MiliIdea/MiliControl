//
//  SymbolicHotKeys.swift
//  MiliControl
//
//  Reads macOS's own keyboard-shortcut table (System Settings ▸ Keyboard ▸
//  Keyboard Shortcuts), stored in the `com.apple.symbolichotkeys` domain.
//  MiliControl uses it to:
//    • find the real key combo for "Switch to Desktop N" (1–16) and
//      "Move left/right a space", so it sends exactly what macOS listens for,
//    • tell the user precisely which shortcut to enable or assign.
//
//  macOS gives Desktops 1–9 default keys (⌃1…⌃9). Desktops 10–16 are listed
//  too but have no key until the user assigns one.
//
//  Read-only: MiliControl never writes system preferences.
//

import Foundation
import CoreGraphics

struct KeyCombo: Equatable {
    let keyCode: CGKeyCode
    /// Only shift / control / option / command bits.
    let flags: CGEventFlags
}

struct SymbolicHotKey {
    let enabled: Bool
    let combo: KeyCombo?
    /// The entry stores a key binding at all. False = macOS's default applies;
    /// true with `combo == nil` = the key was deliberately cleared.
    let hasValue: Bool
}

enum SwitchShortcut: Equatable {
    /// Enabled in System Settings with this combo.
    case enabled(KeyCombo)
    /// Present in System Settings but switched off.
    case disabled
    /// Never configured on this Mac — macOS's default combo (1–9), unconfirmed.
    case unconfirmed(KeyCombo)
    /// No key assigned (Desktops 10–16 until the user sets one).
    case unassigned
}

enum SymbolicHotKeys {

    /// IDs in com.apple.symbolichotkeys.
    enum ID {
        static let missionControl = 32
        static let applicationWindows = 33
        static let moveLeftSpace = 79
        static let moveRightSpace = 81
        /// "Switch to Desktop 1" … "Switch to Desktop 16" are 118 … 133.
        static func switchToDesktop(_ number: Int) -> Int { 117 + number }
    }

    /// Desktops macOS can switch to by shortcut (its per-display maximum).
    static let switchableDesktops = 1 ... 16
    /// Desktops that have a default key (⌃1…⌃9).
    static let defaultShortcutDesktops = 1 ... 9

    static let domainName = "com.apple.symbolichotkeys"
    private static let modifierMask: UInt64 =
        CGEventFlags.maskShift.rawValue | CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue

    /// Virtual key codes of the number row.
    private static let digitKeyCodes: [Int: CGKeyCode] = [
        1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25,
    ]

    /// Whether macOS's shortcut table could be read at all. When it can't,
    /// callers must not claim a shortcut is on or off — they don't know.
    static var isReadable: Bool {
        SystemPreferences.value("AppleSymbolicHotKeys", in: domainName) is [String: Any]
    }

    /// Current shortcut table (live values, briefly cached).
    static func read() -> [Int: SymbolicHotKey] {
        guard let table = SystemPreferences.value("AppleSymbolicHotKeys", in: domainName)
                as? [String: Any] else { return [:] }

        var result: [Int: SymbolicHotKey] = [:]
        for (rawID, rawEntry) in table {
            guard let id = Int(rawID), let entry = rawEntry as? [String: Any] else { continue }
            let enabled = (entry["enabled"] as? NSNumber)?.boolValue ?? false
            var combo: KeyCombo?
            if let value = entry["value"] as? [String: Any],
               let parameters = value["parameters"] as? [NSNumber],
               parameters.count >= 3 {
                let keyCode = parameters[1].intValue
                // Stored modifiers use the same bit layout as CGEventFlags;
                // mask off function/numeric-pad bits that arrows carry.
                let flags = CGEventFlags(rawValue: parameters[2].uint64Value & modifierMask)
                if keyCode != 65535 {                     // 65535 = no key
                    combo = KeyCombo(keyCode: CGKeyCode(keyCode), flags: flags)
                }
            }
            result[id] = SymbolicHotKey(enabled: enabled, combo: combo, hasValue: entry["value"] != nil)
        }
        return result
    }

    /// The "Switch to Desktop N" shortcut, or nil if N is outside 1…16.
    static func switchShortcut(forDesktop number: Int,
                               in table: [Int: SymbolicHotKey]) -> SwitchShortcut? {
        guard switchableDesktops.contains(number) else { return nil }
        let fallback = digitKeyCodes[number].map { KeyCombo(keyCode: $0, flags: .maskControl) }
        guard let entry = table[ID.switchToDesktop(number)] else {
            if let fallback = fallback { return .unconfirmed(fallback) }
            return .unassigned
        }
        let hasKey = entry.combo != nil || (!entry.hasValue && fallback != nil)
        guard entry.enabled else { return hasKey ? .disabled : .unassigned }
        if let combo = entry.combo { return .enabled(combo) }
        // No stored binding → macOS's default key; a cleared key → none.
        if !entry.hasValue, let fallback = fallback { return .enabled(fallback) }
        return .unassigned
    }

    /// A combo MiliControl can send to reach Desktop N directly, if any.
    static func usableSwitchCombo(forDesktop number: Int,
                                  in table: [Int: SymbolicHotKey]) -> KeyCombo? {
        switch switchShortcut(forDesktop: number, in: table) {
        case .enabled(let combo)?, .unconfirmed(let combo)?: return combo
        default: return nil
        }
    }

    /// "Move left/right a space" (⌃← / ⌃→ by default), or nil if turned off.
    static func moveSpaceCombo(left: Bool, in table: [Int: SymbolicHotKey]) -> KeyCombo? {
        let fallback = KeyCombo(keyCode: left ? 123 : 124, flags: .maskControl)
        guard let entry = table[left ? ID.moveLeftSpace : ID.moveRightSpace] else { return fallback }
        guard entry.enabled else { return nil }
        if let combo = entry.combo { return combo }
        return entry.hasValue ? nil : fallback          // cleared key → unusable
    }

    /// True when macOS's own Mission Control shortcut is still ⌃↑, which
    /// would swallow MiliControl's ⌃↑ grid shortcut.
    static func missionControlUsesControlUp(in table: [Int: SymbolicHotKey]) -> Bool {
        guard let entry = table[ID.missionControl] else { return true } // default: on, ⌃↑
        guard entry.enabled else { return false }
        guard let combo = entry.combo else { return true }
        return combo.keyCode == 126 && combo.flags == .maskControl
    }

    /// True when macOS's "Application windows" shortcut is still ⌃↓, which
    /// would swallow ⌃↓ before MiliControl's grid editor can use it to close.
    static func applicationWindowsUsesControlDown(in table: [Int: SymbolicHotKey]) -> Bool {
        guard let entry = table[ID.applicationWindows] else { return true } // default: on, ⌃↓
        guard entry.enabled else { return false }
        guard let combo = entry.combo else { return !entry.hasValue }
        return combo.keyCode == 125 && combo.flags == .maskControl
    }

    // MARK: - Display

    /// Human-readable combo, e.g. "⌃⌥⌘1".
    static func label(for combo: KeyCombo) -> String {
        var text = ""
        if combo.flags.contains(.maskControl) { text += "⌃" }
        if combo.flags.contains(.maskAlternate) { text += "⌥" }
        if combo.flags.contains(.maskShift) { text += "⇧" }
        if combo.flags.contains(.maskCommand) { text += "⌘" }
        return text + (keyNames[combo.keyCode] ?? "key \(combo.keyCode)")
    }

    private static let keyNames: [CGKeyCode: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 50: "`", 36: "↩", 48: "⇥", 49: "Space",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
        100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
