//
//  MessageMonitor.swift
//  MiliControl
//
//  Unread messages from Telegram, WhatsApp and Slack, for the dashboard and
//  the notch.
//
//  macOS gives apps no way to read other apps' notifications, so this uses
//  what's on screen, through Accessibility (which MiliControl already has):
//
//    • Unread counts — the badge on each app's Dock icon ("3", "99+", "•").
//      Reliable; works whether or not the app shows notifications.
//    • Messages — the notification banners as they appear (sender + preview).
//      Only messages that arrive while MiliControl runs, and only if the app's
//      notifications are on. Banners are read from their on-screen text, so a
//      future macOS may change what's picked up; nothing breaks if it does.
//
//  Everything stays in memory: nothing is saved, nothing leaves the Mac.
//  A conversation's messages are dropped once its app has no unread badge.
//

import AppKit
import ApplicationServices
import Combine
import os

enum MessagingApp: String, CaseIterable, Identifiable {
    case telegram, whatsapp, slack

    var id: String { rawValue }

    var name: String {
        switch self {
        case .telegram: return "Telegram"
        case .whatsapp: return "WhatsApp"
        case .slack: return "Slack"
        }
    }

    /// Every build of the app (App Store, direct download, desktop editions).
    var bundleIDs: [String] {
        switch self {
        case .telegram: return ["ru.keepcoder.Telegram", "org.telegram.desktop", "com.tdesktop.Telegram"]
        case .whatsapp: return ["net.whatsapp.WhatsApp", "desktop.WhatsApp", "WhatsApp"]
        case .slack: return ["com.tinyspeck.slackmacgap"]
        }
    }

    static func app(forBundleID id: String) -> MessagingApp? {
        allCases.first { $0.bundleIDs.contains(id) }
    }

    /// The installed (or running) copy, for its icon and for opening it.
    var url: URL? {
        for id in bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
        }
        return nil
    }

    var icon: NSImage? { url.map { NSWorkspace.shared.icon(forFile: $0.path) } }

    func open() {
        guard let url = url else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// A message read from a notification banner.
struct CapturedMessage: Identifiable, Equatable {
    let id = UUID()
    let app: MessagingApp
    /// The chat or person ("Mili", "#design", "Family").
    let sender: String
    let text: String
    let date: Date

    static func == (a: CapturedMessage, b: CapturedMessage) -> Bool { a.id == b.id }
}

final class MessageMonitor: ObservableObject {

    /// The Dock badge per app: "3", "99+", "•"… Missing = nothing unread.
    @Published private(set) var badges: [MessagingApp: String] = [:]
    /// Newest first, at most one per conversation.
    @Published private(set) var messages: [CapturedMessage] = []
    /// Fires for each newly captured message (for the notch peek).
    let newMessage = PassthroughSubject<CapturedMessage, Never>()

    private var badgeTimer: Timer?
    private var bannerTimer: Timer?
    /// Banners already read, by content, with when — a banner stays on screen
    /// for several polls and must count once.
    private var seen: [String: Date] = [:]
    private var bundleIDByDockURL: [URL: String] = [:]
    private let log = Logger(subsystem: "com.mili.MiliControl", category: "messages")

    private static let maxMessages = 20

    var isRunning: Bool { badgeTimer != nil }

    /// Total unread across the apps that show a number.
    var unreadCount: Int {
        badges.values.compactMap { Int($0.filter(\.isNumber)) }.reduce(0, +)
    }

    // MARK: - Start / stop

    func start() {
        guard badgeTimer == nil else { return }
        badgeTimer = Self.timer(every: 2) { [weak self] in self?.readBadges() }
        bannerTimer = Self.timer(every: 0.8) { [weak self] in self?.readBanners() }
        readBadges()
    }

    func stop() {
        badgeTimer?.invalidate()
        bannerTimer?.invalidate()
        badgeTimer = nil
        bannerTimer = nil
        badges = [:]
        messages = []
        seen = [:]
    }

    private static func timer(every interval: TimeInterval, _ block: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in block() }
        timer.tolerance = interval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    // MARK: - Dock badges

    private func readBadges() {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return }
        var found: [MessagingApp: String] = [:]
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        for list in AX.children(root) where AX.string(list, kAXRoleAttribute) == kAXListRole {
            for item in AX.children(list) {
                guard let badge = AX.string(item, "AXStatusLabel"), !badge.isEmpty,
                      let url = AX.url(item), let app = messagingApp(atDockURL: url) else { continue }
                found[app] = badge
            }
        }
        if found != badges { badges = found }
        // Read in the app (badge gone) → forget its messages. A short grace
        // period covers apps that update their badge a moment after the banner.
        let now = Date()
        let isRead: (CapturedMessage) -> Bool = { found[$0.app] == nil && now.timeIntervalSince($0.date) > 10 }
        if messages.contains(where: isRead) { messages.removeAll(where: isRead) }
    }

    private func messagingApp(atDockURL url: URL) -> MessagingApp? {
        if let id = bundleIDByDockURL[url] { return MessagingApp.app(forBundleID: id) }
        guard let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        bundleIDByDockURL[url] = id
        return MessagingApp.app(forBundleID: id)
    }

    // MARK: - Notification banners

    private func readBanners() {
        guard AXIsProcessTrusted(),
              let center = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.notificationcenterui").first else { return }
        let root = AXUIElementCreateApplication(center.processIdentifier)
        // Banners live in Notification Center's windows; some macOS versions
        // only expose them as the app's children.
        var tops = AX.elements(root, kAXWindowsAttribute)
        if tops.isEmpty { tops = AX.children(root) }
        guard !tops.isEmpty else { return }

        var banners: [Banner] = []
        for top in tops { collectBanners(in: top, depth: 0, into: &banners) }
        // Keep the latest non-trivial snapshot (a banner or Notification
        // Center being open) for diagnostics.
        let outline = tops.map { AX.outline($0, maxDepth: 12, maxLines: 80) }.joined(separator: "\n")
        if outline.split(separator: "\n").count > 4 { lastStructure = outline }

        let now = Date()
        seen = seen.filter { now.timeIntervalSince($0.value) < 15 * 60 }
        for banner in banners {
            guard let message = banner.message(at: now) else { continue }
            let fingerprint = "\(message.app.rawValue)|\(message.sender)|\(message.text)"
            guard seen[fingerprint] == nil else { continue }
            seen[fingerprint] = now
            add(message)
        }
    }

    private func add(_ message: CapturedMessage) {
        log.debug("Message from \(message.app.name, privacy: .public)")
        var list = messages.filter { !($0.app == message.app && $0.sender == message.sender) }
        list.insert(message, at: 0)
        messages = Array(list.prefix(Self.maxMessages))
        newMessage.send(message)
    }

    /// One notification: its accessibility description and the texts it shows.
    private struct Banner {
        let description: String
        let texts: [String]

        func message(at date: Date) -> CapturedMessage? {
            // Which app: named in the description or the texts.
            let haystack = ([description] + texts).joined(separator: " ")
            guard let app = MessagingApp.allCases.first(where: { haystack.localizedCaseInsensitiveContains($0.name) })
            else { return nil }

            // Prefer the separate texts; fall back to the description, which
            // reads "Telegram, Mili, See you at 5" on current macOS.
            var parts = clean(texts, removing: app)
            if parts.count < 2 {
                parts = clean(description.components(separatedBy: ", "), removing: app)
            }
            guard let sender = parts.first, parts.count >= 2 else { return nil }
            return CapturedMessage(app: app, sender: sender,
                                   text: parts.dropFirst().joined(separator: " · "), date: date)
        }

        /// Drops the app's own name, time stamps ("now", "2m ago") and blanks.
        private func clean(_ parts: [String], removing app: MessagingApp) -> [String] {
            var seen = Set<String>()
            return parts.compactMap { part -> String? in
                let text = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty,
                      text.caseInsensitiveCompare(app.name) != .orderedSame,
                      !Self.isTimestamp(text),
                      !seen.contains(text) else { return nil }
                seen.insert(text)
                return text
            }
        }

        private static func isTimestamp(_ text: String) -> Bool {
            let lower = text.lowercased()
            if ["now", "just now", "yesterday", "today"].contains(lower) { return true }
            return lower.range(of: #"^\d+\s?(s|m|h|d|min|mins|hr|hrs)( ago)?$"#, options: .regularExpression) != nil
                || lower.range(of: #"^\d{1,2}:\d{2}( ?[ap]m)?$"#, options: .regularExpression) != nil
        }
    }

    /// Finds notifications: elements whose subrole marks them as a banner or
    /// alert (current macOS), or — failing that — the innermost groups that
    /// hold a few texts or a descriptive label.
    private func collectBanners(in element: AXUIElement, depth: Int, into banners: inout [Banner]) {
        guard depth < 16 else { return }
        let subrole = AX.string(element, kAXSubroleAttribute) ?? ""
        let description = AX.string(element, kAXDescriptionAttribute) ?? ""

        // A single notification (not a stack of them).
        if subrole.hasPrefix("AXNotificationCenter"), !subrole.contains("Stack") {
            let texts = AX.texts(in: element, maxDepth: 8)
            if !texts.isEmpty || !description.isEmpty {
                banners.append(Banner(description: description, texts: texts))
                return
            }
        }

        let children = AX.children(element)
        let before = banners.count
        for child in children where AX.string(child, kAXRoleAttribute) != kAXStaticTextRole {
            collectBanners(in: child, depth: depth + 1, into: &banners)
        }
        guard banners.count == before else { return }       // a deeper element matched

        // Fallback for other layouts.
        let role = AX.string(element, kAXRoleAttribute)
        guard role == kAXGroupRole || role == kAXButtonRole else { return }
        let texts = children.filter { AX.string($0, kAXRoleAttribute) == kAXStaticTextRole }
            .compactMap { AX.string($0, kAXValueAttribute) }
        let describesMessage = description.components(separatedBy: ", ").count >= 3
        if texts.count >= 2 || describesMessage {
            banners.append(Banner(description: description, texts: texts))
        }
    }

    /// What MiliControl last saw of Notification Center, for Copy Diagnostics
    /// (so banner reading can be tuned to a macOS version).
    private var lastStructure = ""

    var diagnostics: String {
        var lines = ["Messages: \(isRunning ? "watching" : "off"), Accessibility \(AXIsProcessTrusted() ? "on" : "off")"]
        lines.append("  Badges: " + (badges.isEmpty ? "none" : badges.map { "\($0.key.name) \($0.value)" }.joined(separator: ", ")))
        lines.append("  Captured messages: \(messages.count)")
        lines.append("  Notification Center (last seen):")
        lines.append(lastStructure.isEmpty ? "    (nothing yet — trigger a notification and copy again)"
                                           : lastStructure.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n"))
        return lines.joined(separator: "\n")
    }
}

/// Small Accessibility helpers.
enum AX {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (value(element, attribute) as? [AXUIElement]) ?? []
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        elements(element, kAXChildrenAttribute)
    }

    /// Static texts anywhere inside `element`, in reading order.
    static func texts(in element: AXUIElement, maxDepth: Int) -> [String] {
        var result: [String] = []
        func walk(_ node: AXUIElement, _ depth: Int) {
            guard depth <= maxDepth, result.count < 12 else { return }
            if string(node, kAXRoleAttribute) == kAXStaticTextRole, let text = string(node, kAXValueAttribute) {
                result.append(text)
            }
            children(node).forEach { walk($0, depth + 1) }
        }
        walk(element, 0)
        return result
    }

    /// An indented role / subrole / label outline, for diagnostics.
    static func outline(_ element: AXUIElement, maxDepth: Int, maxLines: Int) -> String {
        var lines: [String] = []
        func walk(_ node: AXUIElement, _ depth: Int) {
            guard depth <= maxDepth, lines.count < maxLines else { return }
            var line = String(repeating: "  ", count: depth) + (string(node, kAXRoleAttribute) ?? "?")
            if let subrole = string(node, kAXSubroleAttribute) { line += "/" + subrole }
            if let label = string(node, kAXDescriptionAttribute), !label.isEmpty { line += " desc=\"\(label.prefix(60))\"" }
            if let value = string(node, kAXValueAttribute), !value.isEmpty { line += " value=\"\(value.prefix(60))\"" }
            lines.append(line)
            children(node).forEach { walk($0, depth + 1) }
        }
        walk(element, 0)
        return lines.joined(separator: "\n")
    }

    static func url(_ element: AXUIElement) -> URL? {
        if let url = value(element, kAXURLAttribute) as? URL { return url }
        return (value(element, kAXURLAttribute) as? String).flatMap(URL.init(string:))
    }
}
