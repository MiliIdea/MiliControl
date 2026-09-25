//
//  WebTabs.swift
//  MiliControl
//
//  Websites you can open inside the grid view — chess.com, YouTube, ChatGPT,
//  anything — from the switcher at its top right.
//
//  Each tab keeps one live web view for as long as MiliControl runs, so a
//  game, video or chat is exactly where you left it when you come back. Tabs
//  you haven't looked at for a while are unloaded to save memory (never the
//  one on screen). Sign-ins are kept in MiliControl's own website data,
//  separate from Safari and Chrome, and survive restarts.
//

import AppKit
import Combine
import WebKit
import os

struct WebTab: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var url: URL

    init(id: UUID = UUID(), title: String, url: URL) {
        self.id = id
        self.title = title
        self.url = url
    }

    static let defaults = [WebTab(title: "Chess", url: URL(string: "https://www.chess.com")!)]

    /// "chess.com" → https://chess.com; keeps full URLs as they are.
    static func url(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard let url = URL(string: trimmed), let host = url.host, host.contains("."),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    /// A readable default name: "www.chess.com" → "Chess".
    static func suggestedTitle(for url: URL) -> String {
        let host = (url.host ?? url.absoluteString).replacingOccurrences(of: "www.", with: "")
        let name = host.split(separator: ".").first.map(String.init) ?? host
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

final class WebTabsStore: NSObject, ObservableObject {

    /// Site icons, by tab.
    @Published private(set) var icons: [UUID: NSImage] = [:]
    /// Live page state for the toolbar.
    @Published private(set) var canGoBack: [UUID: Bool] = [:]
    @Published private(set) var canGoForward: [UUID: Bool] = [:]
    @Published private(set) var isLoading: [UUID: Bool] = [:]

    private let prefs: Preferences
    private var webViews: [UUID: WKWebView] = [:]
    private var lastShown: [UUID: Date] = [:]
    private var visibleTab: UUID?
    private var observations: [UUID: [NSKeyValueObservation]] = [:]
    private var unloadTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let log = Logger(subsystem: "com.mili.MiliControl", category: "webtabs")

    /// Unload tabs not looked at for this long.
    private static let idleUnload: TimeInterval = 30 * 60
    /// A current Safari identity, so sites serve their full desktop version.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    init(prefs: Preferences) {
        self.prefs = prefs
        super.init()
        // Tabs removed in Settings: let their pages go.
        prefs.$webTabs
            .receive(on: RunLoop.main)
            .sink { [weak self] tabs in
                guard let self = self else { return }
                let live = Set(tabs.map(\.id))
                for id in self.webViews.keys where !live.contains(id) { self.unload(id) }
                tabs.forEach { self.loadIcon(for: $0) }
            }
            .store(in: &cancellables)

        let timer = Timer(timeInterval: 5 * 60, repeats: true) { [weak self] _ in self?.unloadIdleTabs() }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        unloadTimer = timer
    }

    var tabs: [WebTab] { prefs.webTabs }

    /// The tab's web view, created (and its site loaded) on first use.
    func webView(for tab: WebTab) -> WKWebView {
        if let existing = webViews[tab.id] { return existing }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()               // persistent sign-ins
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.userAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.load(URLRequest(url: tab.url))
        webViews[tab.id] = webView
        observe(webView, id: tab.id)
        return webView
    }

    /// The grid view shows `tab` now (nil = the desktops).
    func show(_ tab: WebTab?) {
        if let previous = visibleTab { lastShown[previous] = Date() }
        visibleTab = tab?.id
        if let tab = tab { lastShown[tab.id] = Date() }
    }

    func goBack(_ tab: WebTab) { webViews[tab.id]?.goBack() }
    func goForward(_ tab: WebTab) { webViews[tab.id]?.goForward() }
    func reload(_ tab: WebTab) { webViews[tab.id]?.reload() }
    /// Back to the tab's own address.
    func goHome(_ tab: WebTab) { webViews[tab.id]?.load(URLRequest(url: tab.url)) }

    func openInBrowser(_ tab: WebTab) {
        NSWorkspace.shared.open(webViews[tab.id]?.url ?? tab.url)
    }

    // MARK: - Memory

    private func unloadIdleTabs() {
        let now = Date()
        for id in webViews.keys where id != visibleTab {
            if let shown = lastShown[id], now.timeIntervalSince(shown) > Self.idleUnload { unload(id) }
        }
    }

    private func unload(_ id: UUID) {
        guard let webView = webViews.removeValue(forKey: id) else { return }
        observations[id] = nil
        webView.stopLoading()
        webView.removeFromSuperview()
        canGoBack[id] = nil
        canGoForward[id] = nil
        isLoading[id] = nil
        log.debug("Unloaded an idle web tab")
    }

    private func observe(_ webView: WKWebView, id: UUID) {
        observations[id] = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.canGoBack[id] = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.canGoForward[id] = view.canGoForward }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.isLoading[id] = view.isLoading }
            },
        ]
    }

    // MARK: - Icons

    /// The site's touch icon (sharp) or favicon, fetched from the site itself.
    private func loadIcon(for tab: WebTab) {
        guard icons[tab.id] == nil, let host = tab.url.host, let scheme = tab.url.scheme else { return }
        let candidates = ["/apple-touch-icon.png", "/favicon.ico"].compactMap { URL(string: "\(scheme)://\(host)\($0)") }
        fetchFirstIcon(candidates, for: tab.id)
    }

    private func fetchFirstIcon(_ urls: [URL], for id: UUID) {
        guard let url = urls.first else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200 ..< 300).contains($0.statusCode) } ?? false
            if ok, let data = data, let image = NSImage(data: data), image.isValid {
                DispatchQueue.main.async { self?.icons[id] = image }
            } else {
                self?.fetchFirstIcon(Array(urls.dropFirst()), for: id)
            }
        }.resume()
    }
}

// MARK: - Web view behaviour

extension WebTabsStore: WKUIDelegate, WKNavigationDelegate {

    /// Links that open a new window (target=_blank, sign-in pop-ups) open in
    /// the same tab.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    /// Non-web links (mailto:, app links) go to the app that handles them.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "blob", "data"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    /// Camera and microphone stay off in web tabs (MiliControl never asks
    /// macOS for them); use your browser for video calls.
    @available(macOS 12.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    /// JavaScript alerts ("Are you sure you want to resign?").
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        if let window = webView.window {
            alert.beginSheetModal(for: window) { _ in completionHandler() }
        } else {
            alert.runModal()
            completionHandler()
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if let window = webView.window {
            alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
        } else {
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }
    }
}
