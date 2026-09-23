//
//  DesktopStore.swift
//  MiliControl
//
//  Live view of the Mac's regular desktops (fullscreen-app spaces are
//  excluded) and which one is active. Also knows which apps have windows on
//  each desktop, for tile labels and icons.
//
//  Desktop identity: each desktop gets a stable `key` — the space's UUID.
//  macOS reports an empty UUID for the original desktop of each display, so
//  that one is keyed "primary:<display>". Space IDs themselves can change
//  across restarts, which is why the layout never stores them.
//

import AppKit
import Combine
import os

struct Desktop: Identifiable, Equatable {
    /// Stable identity used by the grid layout.
    let key: String
    let spaceID: CGSSpaceID
    /// macOS's own numbering ("Desktop N"), which is what the
    /// "Switch to Desktop N" shortcut targets. 1-based.
    let number: Int
    let displayID: String

    var id: String { key }
}

struct AppSummary: Equatable, Identifiable {
    let name: String
    let pid: pid_t
    var id: pid_t { pid }
}

final class DesktopStore: ObservableObject {

    @Published private(set) var desktops: [Desktop] = []
    /// Key of the focused desktop, or nil when a fullscreen app has focus.
    @Published private(set) var currentKey: String?
    /// Apps with visible windows on each desktop, front to back.
    @Published private(set) var apps: [String: [AppSummary]] = [:]

    /// Each display's spaces in macOS's strip order, fullscreen apps included
    /// — what "Move left/right a space" walks through (it never crosses
    /// displays). Keyed by display identifier.
    private(set) var strips: [String: [CGSSpaceID]] = [:]
    /// The focused space (may be a fullscreen app, unlike `currentKey`).
    private(set) var activeSpaceID: CGSSpaceID = 0

    private let connection = CGSMainConnectionID()
    private var workspaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "com.mili.MiliControl", category: "desktops")

    init() {
        refresh()
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
    }

    deinit {
        if let o = workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        if let o = screenObserver { NotificationCenter.default.removeObserver(o) }
    }

    func desktop(forKey key: String) -> Desktop? {
        desktops.first { $0.key == key }
    }

    // MARK: - Reading spaces

    /// Re-reads desktops and the active space from the window server.
    /// Cheap enough to call on every hotkey press.
    func refresh() {
        let active = CGSGetActiveSpace(connection)
        // nil (window server refused / not ready) → treat as "no desktops yet";
        // the layout keeps its saved arrangement until a real answer arrives.
        let displays = (CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]]) ?? []

        var result: [Desktop] = []
        var current: String?
        var number = 0
        var usedKeys = Set<String>()
        var stripsByDisplay: [String: [CGSSpaceID]] = [:]

        for display in displays {
            let displayID = display["Display Identifier"] as? String ?? "Main"
            let spaces = display["Spaces"] as? [[String: Any]] ?? []
            for space in spaces {
                let spaceID = Self.uint64(space["ManagedSpaceID"]) ?? Self.uint64(space["id64"]) ?? 0
                guard spaceID != 0 else { continue }
                stripsByDisplay[displayID, default: []].append(spaceID)
                // 0 = regular desktop. Fullscreen apps (4) aren't numbered
                // desktops and can't be targeted by "Switch to Desktop N".
                let type = (space["type"] as? NSNumber)?.intValue ?? 0
                guard type == 0 else { continue }

                number += 1
                let uuid = space["uuid"] as? String ?? ""
                var key = uuid.isEmpty ? "primary:\(displayID)" : uuid
                // Keys must be unique (e.g. when spaces from a disconnected
                // display merge onto another one).
                if usedKeys.contains(key) { key += "#\(spaceID)" }
                usedKeys.insert(key)
                result.append(Desktop(key: key, spaceID: spaceID, number: number, displayID: displayID))
                if spaceID == active { current = key }
            }
        }

        strips = stripsByDisplay
        activeSpaceID = active
        if result != desktops {
            log.debug("Desktops changed: \(result.count, privacy: .public)")
            desktops = result
        }
        if current != currentKey { currentKey = current }
    }

    // MARK: - Apps per desktop

    /// Rebuilds which apps have windows on each desktop. Uses only window
    /// owner names (no window titles), so it needs no Screen Recording access.
    func refreshApps() {
        let info = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]]) ?? []
        var byNumber: [Int: [String: Any]] = [:]
        for window in info {
            if let n = (window[kCGWindowNumber as String] as? NSNumber)?.intValue {
                byNumber[n] = window
            }
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var result: [String: [AppSummary]] = [:]

        for desktop in desktops {
            var setTags: UInt64 = 0
            var clearTags: UInt64 = 0
            let spaces = [NSNumber(value: desktop.spaceID)] as CFArray
            let ids = (CGSCopyWindowsWithOptionsAndTags(connection, 0, spaces, 0x2,
                                                        &setTags, &clearTags) as? [NSNumber]) ?? []

            var seen = Set<pid_t>()
            var summaries: [AppSummary] = []
            for id in ids {
                guard let window = byNumber[id.intValue] else { continue }
                let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
                guard layer == 0 else { continue }                     // normal windows only
                let pid = pid_t((window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0)
                guard pid != 0, pid != ownPID, !seen.contains(pid) else { continue }
                if let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                   let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                   bounds.width < 60 || bounds.height < 60 { continue } // helper/invisible windows
                let name = window[kCGWindowOwnerName as String] as? String ?? ""
                guard !name.isEmpty else { continue }
                seen.insert(pid)
                summaries.append(AppSummary(name: name, pid: pid))
            }
            result[desktop.key] = summaries
        }

        if result != apps { apps = result }
    }

    /// "Safari", "Safari +2", or nil for an empty desktop.
    func title(forKey key: String) -> String? {
        let list = apps[key] ?? []
        guard let first = list.first else { return nil }
        return list.count == 1 ? first.name : "\(first.name) +\(list.count - 1)"
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        (value as? NSNumber)?.uint64Value
    }
}

/// App icons by process, cached.
final class IconCache {
    static let shared = IconCache()
    private var cache: [pid_t: NSImage] = [:]

    func icon(for pid: pid_t) -> NSImage? {
        if let cached = cache[pid] { return cached }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        if let icon = icon { cache[pid] = icon }
        return icon
    }
}
