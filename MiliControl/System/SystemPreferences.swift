//
//  SystemPreferences.swift
//  MiliControl
//
//  Reads other apps' / macOS's preference domains (com.apple.dock,
//  com.apple.symbolichotkeys, trackpad settings…) reliably.
//
//  1. CFPreferences — fast, in-process.
//  2. If that yields nothing, `/usr/bin/defaults export <domain> -` — the
//     same tool Terminal uses, which always gets the live values from the
//     preferences daemon. Some macOS versions/configurations return nothing
//     to method 1 for another app's domain.
//
//  Results are cached briefly, so hot paths (a desktop switch) stay cheap.
//  Read-only: MiliControl never writes these domains.
//

import Foundation
import os

enum SystemPreferences {

    /// How a domain was obtained (reported in diagnostics).
    enum Source: String { case cfPreferences = "CFPreferences", defaultsTool = "defaults", unavailable }

    private struct Entry {
        let values: [String: Any]?
        let source: Source
        let time: Date
    }

    private static var cache: [String: Entry] = [:]
    private static let lock = NSLock()
    /// CFPreferences is cheap, so re-read often; the `defaults` fallback spawns
    /// a process, so its results (and "unavailable") are kept longer.
    private static let fastTTL: TimeInterval = 1.5
    private static let slowTTL: TimeInterval = 30
    /// Hard limit for the `defaults` tool, so a stuck preferences daemon can
    /// never freeze MiliControl.
    private static let toolTimeout: TimeInterval = 2
    private static let log = Logger(subsystem: "com.mili.MiliControl", category: "preferences")

    /// All values in `domain`, or nil if it couldn't be read at all.
    static func domain(_ name: String) -> [String: Any]? {
        read(name).values
    }

    /// How `domain` was read the last time (for diagnostics).
    static func source(of name: String) -> Source {
        read(name).source
    }

    static func value(_ key: String, in domain: String) -> Any? {
        self.domain(domain)?[key]
    }

    /// Drops cached values (e.g. when the user presses "Check Again").
    static func invalidate() {
        lock.lock(); cache.removeAll(); lock.unlock()
    }

    // MARK: - Reading

    private static func read(_ name: String) -> Entry {
        lock.lock()
        if let cached = cache[name] {
            let ttl = cached.source == .cfPreferences ? fastTTL : slowTTL
            if Date().timeIntervalSince(cached.time) < ttl {
                lock.unlock()
                return cached
            }
        }
        lock.unlock()

        let entry: Entry
        if let values = readWithCFPreferences(name), !values.isEmpty {
            entry = Entry(values: values, source: .cfPreferences, time: Date())
        } else if let values = readWithDefaultsTool(name) {
            entry = Entry(values: values, source: .defaultsTool, time: Date())
        } else {
            entry = Entry(values: nil, source: .unavailable, time: Date())
            log.error("Couldn't read preference domain \(name, privacy: .public)")
        }

        lock.lock(); cache[name] = entry; lock.unlock()
        return entry
    }

    private static func readWithCFPreferences(_ name: String) -> [String: Any]? {
        let domain = name as CFString
        CFPreferencesAppSynchronize(domain)
        let all = CFPreferencesCopyMultiple(nil, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return all as? [String: Any]
    }

    private static func readWithDefaultsTool(_ name: String) -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["export", name, "-"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }

        // Read on a background queue and wait with a timeout.
        var data = Data()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            done.signal()
        }
        guard done.wait(timeout: .now() + toolTimeout) == .success else {
            process.terminate()
            log.error("`defaults export \(name, privacy: .public)` timed out")
            return nil
        }
        guard process.terminationStatus == 0, !data.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return nil }
        return plist as? [String: Any]
    }

    /// A value from the current host's global domain (where recent macOS
    /// keeps some trackpad gesture settings).
    static func currentHostGlobalValue(_ key: String) -> Any? {
        CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication,
                               kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
}
