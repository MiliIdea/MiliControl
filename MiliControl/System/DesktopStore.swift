//
//  DesktopStore.swift
//  MiliControl
//
//  Live view of the Mac's spaces: numbered desktops, fullscreen apps (and
//  Split View pairs), and which one is active. Also knows which apps have
//  windows on each, for tile labels and icons.
//
//  Identity: each space gets a stable `key` the layout stores.
//    • Desktops — the space's UUID. macOS reports an empty UUID for the
//      original desktop of each display, so that one is "primary:<display>".
//    • Fullscreen apps — "fullscreen:<bundle ID>" ("…:<A>+<B>" for Split
//      View). A fullscreen space is created and destroyed with the window, so
//      the key names the app instead: leave fullscreen and come back, and it
//      returns to the same slot in the grid.
//  Space IDs themselves can change across restarts and are never stored.
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

/// One app window that fills a fullscreen space.
struct FullscreenApp: Equatable {
    let pid: pid_t
    let bundleID: String
    let name: String
    /// The fullscreen window, when known (used to raise exactly that window).
    let windowID: CGWindowID?
}

/// A fullscreen app — or two, side by side in Split View.
struct FullscreenSpace: Identifiable, Equatable {
    static let keyPrefix = "fullscreen:"

    let key: String
    let spaceID: CGSSpaceID
    let displayID: String
    /// Left to right.
    let apps: [FullscreenApp]

    var id: String { key }
    /// "Figma" or "Safari + Notes".
    var title: String { apps.map(\.name).joined(separator: " + ") }

    static func isKey(_ key: String) -> Bool { key.hasPrefix(keyPrefix) }
}

/// Anything that can sit in the grid.
enum GridSpace: Equatable {
    case desktop(Desktop)
    case fullscreen(FullscreenSpace)

    var key: String {
        switch self {
        case .desktop(let d): return d.key
        case .fullscreen(let f): return f.key
        }
    }
    var spaceID: CGSSpaceID {
        switch self {
        case .desktop(let d): return d.spaceID
        case .fullscreen(let f): return f.spaceID
        }
    }
    var displayID: String {
        switch self {
        case .desktop(let d): return d.displayID
        case .fullscreen(let f): return f.displayID
        }
    }
    /// macOS's desktop number; nil for fullscreen apps (they have none).
    var number: Int? {
        if case .desktop(let d) = self { return d.number }
        return nil
    }
    /// "Desktop 3" or "Figma (fullscreen)" — for messages.
    var name: String {
        switch self {
        case .desktop(let d): return "Desktop \(d.number)"
        case .fullscreen(let f): return "\(f.title) (fullscreen)"
        }
    }
}

struct AppSummary: Equatable, Identifiable {
    let name: String
    let pid: pid_t
    /// Browser profiles of this app's windows on the desktop (Chrome & co.).
    var profiles: [BrowserProfile] = []
    var id: pid_t { pid }

    /// "Google Chrome", or "Google Chrome · Work" / "Google Chrome · Work, Home".
    var label: String {
        profiles.isEmpty ? name : "\(name) · \(profiles.map(\.name).joined(separator: ", "))"
    }
}

final class DesktopStore: ObservableObject {

    /// Numbered desktops only ("Desktop 1…N").
    @Published private(set) var desktops: [Desktop] = []
    /// Fullscreen apps and Split View pairs, in strip order.
    @Published private(set) var fullscreens: [FullscreenSpace] = []
    /// Key of the focused space — a desktop or a fullscreen app.
    @Published private(set) var currentKey: String?
    /// Apps with visible windows on each space, front to back.
    @Published private(set) var apps: [String: [AppSummary]] = [:]

    /// Every grid key (desktops and fullscreen apps) in macOS's own order:
    /// display by display, left to right as in Mission Control.
    private(set) var orderedKeys: [String] = []

    /// Each display's spaces in macOS's strip order, fullscreen apps included
    /// — what "Move left/right a space" walks through (it never crosses
    /// displays). Keyed by display identifier.
    private(set) var strips: [String: [CGSSpaceID]] = [:]
    /// The focused space (may be a fullscreen app, unlike `currentKey`).
    private(set) var activeSpaceID: CGSSpaceID = 0

    private let connection = CGSMainConnectionID()
    private let bundleIDs = BundleIDCache()
    /// Who's in each fullscreen space (fixed for the space's lifetime).
    private var fullscreenApps: [CGSSpaceID: [FullscreenApp]] = [:]
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

    /// The desktop or fullscreen app with this key, if it exists right now.
    func space(forKey key: String) -> GridSpace? {
        if let desktop = desktop(forKey: key) { return .desktop(desktop) }
        return fullscreens.first { $0.key == key }.map(GridSpace.fullscreen)
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
        var fullscreenResult: [FullscreenSpace] = []
        var ordered: [String] = []
        var current: String?
        var number = 0
        var usedKeys = Set<String>()
        var stripsByDisplay: [String: [CGSSpaceID]] = [:]
        var liveSpaces = Set<CGSSpaceID>()

        for display in displays {
            let displayID = display["Display Identifier"] as? String ?? "Main"
            let spaces = display["Spaces"] as? [[String: Any]] ?? []
            for space in spaces {
                let spaceID = Self.uint64(space["ManagedSpaceID"]) ?? Self.uint64(space["id64"]) ?? 0
                guard spaceID != 0 else { continue }
                stripsByDisplay[displayID, default: []].append(spaceID)
                liveSpaces.insert(spaceID)
                // 0 = regular desktop, 4 = fullscreen app / Split View.
                let type = (space["type"] as? NSNumber)?.intValue ?? 0
                let key: String

                switch type {
                case 0:
                    number += 1
                    let uuid = space["uuid"] as? String ?? ""
                    key = Self.unique(uuid.isEmpty ? "primary:\(displayID)" : uuid, spaceID, &usedKeys)
                    result.append(Desktop(key: key, spaceID: spaceID, number: number, displayID: displayID))
                case 4:
                    let apps = fullscreenApps[spaceID] ?? readFullscreenApps(space, spaceID: spaceID)
                    guard !apps.isEmpty else { continue }       // not ready yet; next refresh
                    fullscreenApps[spaceID] = apps
                    let base = FullscreenSpace.keyPrefix + apps.map(\.bundleID).joined(separator: "+")
                    // Two fullscreen windows of the same app: "…", "…:2", …
                    var candidate = base
                    var index = 1
                    while usedKeys.contains(candidate) { index += 1; candidate = "\(base):\(index)" }
                    usedKeys.insert(candidate)
                    key = candidate
                    fullscreenResult.append(FullscreenSpace(key: key, spaceID: spaceID,
                                                            displayID: displayID, apps: apps))
                default:
                    continue
                }
                ordered.append(key)
                if spaceID == active { current = key }
            }
        }

        fullscreenApps = fullscreenApps.filter { liveSpaces.contains($0.key) }
        strips = stripsByDisplay
        activeSpaceID = active
        orderedKeys = ordered
        if result != desktops {
            log.debug("Desktops changed: \(result.count, privacy: .public)")
            desktops = result
        }
        if fullscreenResult != fullscreens {
            log.debug("Fullscreen apps changed: \(fullscreenResult.count, privacy: .public)")
            fullscreens = fullscreenResult
        }
        if current != currentKey { currentKey = current }
    }

    /// Keys must be unique (e.g. when spaces from a disconnected display
    /// merge onto another one).
    private static func unique(_ key: String, _ spaceID: CGSSpaceID, _ used: inout Set<String>) -> String {
        let result = used.contains(key) ? "\(key)#\(spaceID)" : key
        used.insert(result)
        return result
    }

    // MARK: - Fullscreen spaces

    /// Who's in a fullscreen space: from the window server's description of
    /// the space when it says, otherwise from the windows on it.
    private func readFullscreenApps(_ space: [String: Any], spaceID: CGSSpaceID) -> [FullscreenApp] {
        // Split View lists its tiles; a single fullscreen app has pid/fs_wid.
        var described: [(pid: pid_t, window: CGWindowID?)] = []
        if let manager = space["TileLayoutManager"] as? [String: Any],
           let tiles = manager["TileSpaces"] as? [[String: Any]] {
            for tile in tiles {
                if let pid = (tile["pid"] as? NSNumber)?.int32Value, pid > 0 {
                    described.append((pid, (tile["wid"] as? NSNumber).map { CGWindowID($0.uint32Value) }))
                }
            }
        }
        if described.isEmpty, let pid = (space["pid"] as? NSNumber)?.int32Value, pid > 0 {
            described.append((pid, (space["fs_wid"] as? NSNumber).map { CGWindowID($0.uint32Value) }))
        }
        if described.isEmpty {
            described = windows(onSpace: spaceID, info: Self.windowInfo())
                .map { (pid: $0.pid, window: Optional($0.id)) }
        }

        var apps: [FullscreenApp] = []
        for entry in described where !apps.contains(where: { $0.pid == entry.pid && $0.windowID == entry.window }) {
            guard let running = NSRunningApplication(processIdentifier: entry.pid),
                  let bundleID = running.bundleIdentifier else { continue }
            apps.append(FullscreenApp(pid: entry.pid, bundleID: bundleID,
                                      name: running.localizedName ?? bundleID,
                                      windowID: entry.window))
        }
        return apps
    }

    // MARK: - Windows

    private struct SpaceWindow {
        let id: CGWindowID
        let pid: pid_t
        let ownerName: String
        let title: String?
    }

    private static func windowInfo() -> [Int: [String: Any]] {
        let info = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]]) ?? []
        var byNumber: [Int: [String: Any]] = [:]
        for window in info {
            if let n = (window[kCGWindowNumber as String] as? NSNumber)?.intValue { byNumber[n] = window }
        }
        return byNumber
    }

    /// Normal, visible-size windows of other apps on one space, front to back.
    private func windows(onSpace spaceID: CGSSpaceID, info: [Int: [String: Any]]) -> [SpaceWindow] {
        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0
        let spaces = [NSNumber(value: spaceID)] as CFArray
        let ids = (CGSCopyWindowsWithOptionsAndTags(connection, 0, spaces, 0x2,
                                                    &setTags, &clearTags) as? [NSNumber]) ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return ids.compactMap { id -> SpaceWindow? in
            guard let window = info[id.intValue] else { return nil }
            let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { return nil }                              // normal windows only
            let pid = pid_t((window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0)
            guard pid != 0, pid != ownPID else { return nil }
            if let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
               let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
               bounds.width < 60 || bounds.height < 60 { return nil }          // helper/invisible windows
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let title = window[kCGWindowName as String] as? String
            return SpaceWindow(id: CGWindowID(id.uint32Value), pid: pid, ownerName: owner,
                               title: title?.isEmpty == false ? title : nil)
        }
    }

    // MARK: - Apps per desktop

    /// Rebuilds which apps have windows on each desktop. App names need no
    /// permission; browser profiles are read from window titles, which macOS
    /// only shares with Screen Recording access (otherwise they're skipped).
    func refreshApps() {
        let info = Self.windowInfo()
        var result: [String: [AppSummary]] = [:]
        let spaces: [(key: String, spaceID: CGSSpaceID)] =
            desktops.map { ($0.key, $0.spaceID) } + fullscreens.map { ($0.key, $0.spaceID) }

        for space in spaces {
            var summaries: [AppSummary] = []
            var titles: [pid_t: [String]] = [:]
            for window in windows(onSpace: space.spaceID, info: info) {
                if let title = window.title { titles[window.pid, default: []].append(title) }
                guard !summaries.contains(where: { $0.pid == window.pid }),
                      !window.ownerName.isEmpty else { continue }
                summaries.append(AppSummary(name: window.ownerName, pid: window.pid))
            }
            for index in summaries.indices {
                let pid = summaries[index].pid
                let bundleID = bundleIDs.bundleID(for: pid)
                guard BrowserProfiles.shared.isBrowser(bundleID), let bundleID = bundleID,
                      let windowTitles = titles[pid] else { continue }
                summaries[index].profiles = BrowserProfiles.shared.profiles(bundleID: bundleID,
                                                                            windowTitles: windowTitles)
            }
            result[space.key] = summaries
        }

        if result != apps { apps = result }
    }

    /// "Safari", "Google Chrome · Work", "Safari +2", or nil for an empty desktop.
    func title(forKey key: String) -> String? {
        let list = apps[key] ?? []
        guard let first = list.first else { return nil }
        return list.count == 1 ? first.label : "\(first.label) +\(list.count - 1)"
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        (value as? NSNumber)?.uint64Value
    }
}

/// Bundle identifiers by process, cached (processes don't change bundles).
private final class BundleIDCache {
    private var cache: [pid_t: String] = [:]

    func bundleID(for pid: pid_t) -> String? {
        if let cached = cache[pid] { return cached }
        let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        if let id = id { cache[pid] = id }
        return id
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
