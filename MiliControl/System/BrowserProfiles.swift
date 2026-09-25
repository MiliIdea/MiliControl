//
//  BrowserProfiles.swift
//  MiliControl
//
//  Which Chrome (or Edge, Brave, Vivaldi, Chromium) profile a window belongs
//  to, so a tile can say "Google Chrome · Work" and show the profile's
//  picture.
//
//  With more than one profile, Chromium browsers put the profile's name in
//  the window title ("Inbox - Google Chrome - Work"). The profiles themselves
//  — names, colours, pictures — are listed in the browser's "Local State"
//  file, which is read (never written) and cached until it changes.
//
//  Window titles come from the window server and need Screen Recording
//  (the same permission as desktop previews); without it, no profiles show.
//

import AppKit
import os

struct BrowserProfile: Identifiable, Equatable {
    /// Browser bundle ID + profile folder ("Default", "Profile 2"…).
    let id: String
    let name: String
    let color: NSColor?
    let picture: NSImage?

    static func == (a: BrowserProfile, b: BrowserProfile) -> Bool {
        a.id == b.id && a.name == b.name
    }

    var initial: String {
        name.first.map { String($0).uppercased() } ?? "?"
    }
}

final class BrowserProfiles {

    static let shared = BrowserProfiles()

    /// A Chromium browser: its bundle ID and where it keeps "Local State"
    /// (relative to ~/Library/Application Support).
    private struct Browser {
        let bundleID: String
        let supportFolder: String
    }

    private static let browsers: [Browser] = [
        Browser(bundleID: "com.google.Chrome", supportFolder: "Google/Chrome"),
        Browser(bundleID: "com.google.Chrome.beta", supportFolder: "Google/Chrome Beta"),
        Browser(bundleID: "com.google.Chrome.canary", supportFolder: "Google/Chrome Canary"),
        Browser(bundleID: "com.microsoft.edgemac", supportFolder: "Microsoft Edge"),
        Browser(bundleID: "com.brave.Browser", supportFolder: "BraveSoftware/Brave-Browser"),
        Browser(bundleID: "com.vivaldi.Vivaldi", supportFolder: "Vivaldi"),
        Browser(bundleID: "org.chromium.Chromium", supportFolder: "Chromium"),
    ]

    private struct Cached {
        let modified: Date
        let profiles: [BrowserProfile]
    }

    private var cache: [String: Cached] = [:]
    private let log = Logger(subsystem: "com.mili.MiliControl", category: "profiles")

    func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID = bundleID else { return false }
        return Self.browsers.contains { $0.bundleID == bundleID }
    }

    /// The profiles behind these window titles, in first-seen order and
    /// without duplicates. Empty for single-profile setups (the title has no
    /// profile name then) or when titles aren't readable.
    func profiles(bundleID: String, windowTitles: [String]) -> [BrowserProfile] {
        let known = profiles(for: bundleID)
        guard known.count > 1 else { return [] }
        // Longest names first, so "Work Team" wins over "Work".
        let candidates = known.sorted { $0.name.count > $1.name.count }

        var found: [BrowserProfile] = []
        for title in windowTitles {
            guard let profile = Self.match(title: title, among: candidates),
                  !found.contains(profile) else { continue }
            found.append(profile)
        }
        return found
    }

    /// Titles look like "<page> - <browser> - <profile>" (Chrome) or
    /// "<page> - <profile> - <browser>" (Edge). The page part can contain
    /// " - " itself, so only the trailing parts are compared, and only
    /// against real profile names.
    private static func match(title: String, among profiles: [BrowserProfile]) -> BrowserProfile? {
        let parts = title.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { return nil }
        let tail = Set(parts.suffix(2))
        return profiles.first { tail.contains($0.name) }
    }

    // MARK: - Local State

    private func profiles(for bundleID: String) -> [BrowserProfile] {
        guard let browser = Self.browsers.first(where: { $0.bundleID == bundleID }),
              let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first else { return [] }
        let root = support.appendingPathComponent(browser.supportFolder, isDirectory: true)
        let file = root.appendingPathComponent("Local State")
        guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate else { return [] }
        if let cached = cache[bundleID], cached.modified == modified { return cached.profiles }

        let profiles = Self.readProfiles(bundleID: bundleID, root: root, localState: file)
        cache[bundleID] = Cached(modified: modified, profiles: profiles)
        log.debug("\(bundleID, privacy: .public): \(profiles.count, privacy: .public) profile(s)")
        return profiles
    }

    private static func readProfiles(bundleID: String, root: URL, localState: URL) -> [BrowserProfile] {
        guard let data = try? Data(contentsOf: localState),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: [String: Any]] else { return [] }

        return infoCache.compactMap { folder, info in
            guard let name = info["name"] as? String, !name.isEmpty else { return nil }
            // The account picture, when the profile is signed in and uses it.
            var picture: NSImage?
            if let file = info["gaia_picture_file_name"] as? String, !file.isEmpty,
               (info["use_gaia_picture"] as? Bool) ?? true {
                picture = NSImage(contentsOf: root.appendingPathComponent(folder).appendingPathComponent(file))
            }
            let colorValue = info["profile_highlight_color"] ?? info["default_avatar_fill_color"]
            return BrowserProfile(id: "\(bundleID)/\(folder)", name: name,
                                  color: (colorValue as? NSNumber).map(color(fromSkia:)),
                                  picture: picture)
        }
        .sorted { $0.id < $1.id }
    }

    /// Chromium stores colours as signed 32-bit ARGB integers.
    private static func color(fromSkia value: NSNumber) -> NSColor {
        let argb = UInt32(truncatingIfNeeded: value.int64Value)
        return NSColor(srgbRed: CGFloat((argb >> 16) & 0xFF) / 255,
                       green: CGFloat((argb >> 8) & 0xFF) / 255,
                       blue: CGFloat(argb & 0xFF) / 255,
                       alpha: 1)
    }
}
