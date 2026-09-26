//
//  WebTabViews.swift
//  MiliControl
//
//  The grid view's switcher (desktops ⇄ web tabs, top right) and the page
//  that shows a web tab: a slim toolbar over the site itself.
//

import SwiftUI
import AppKit
import WebKit

/// Top-right switcher: the grid, then one button per web tab.
struct GridTabSwitcher: View {
    @ObservedObject var store: WebTabsStore
    let tabs: [WebTab]
    @Binding var selected: UUID?

    var body: some View {
        HStack(spacing: 2) {
            button(isSelected: selected == nil, help: "Desktops") {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 13, weight: .semibold))
            } action: { selected = nil }

            ForEach(tabs) { tab in
                button(isSelected: selected == tab.id, help: tab.title) {
                    TabIcon(tab: tab, image: store.icons[tab.id])
                } action: { selected = tab.id }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func button<Label: View>(isSelected: Bool, help: String,
                                     @ViewBuilder label: () -> Label,
                                     action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { action() }
        }) {
            label()
                .frame(width: 34, height: 28)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .background(Capsule().fill(isSelected ? Color.white.opacity(0.18) : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The site's icon, or its initial when it has none.
struct TabIcon: View {
    let tab: WebTab
    let image: NSImage?

    var body: some View {
        if let image = image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Text(tab.title.prefix(1).uppercased())
                .font(.system(size: 12, weight: .bold))
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.15)))
        }
    }
}

/// A web tab filling the grid view: toolbar, then the page.
struct WebTabPage: View {
    @ObservedObject var store: WebTabsStore
    let tab: WebTab

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                toolbarButton("chevron.left", help: "Back", enabled: store.canGoBack[tab.id] ?? false) {
                    store.goBack(tab)
                }
                toolbarButton("chevron.right", help: "Forward", enabled: store.canGoForward[tab.id] ?? false) {
                    store.goForward(tab)
                }
                toolbarButton(store.isLoading[tab.id] == true ? "xmark" : "arrow.clockwise",
                              help: "Reload", enabled: true) { store.reload(tab) }
                toolbarButton("house", help: "Go to \(tab.url.host ?? tab.title)", enabled: true) {
                    store.goHome(tab)
                }
                Text(tab.title)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.leading, 6)
                Spacer()
                toolbarButton("safari", help: "Open in your browser", enabled: true) { store.openInBrowser(tab) }
            }
            .frame(height: 30)

            WebViewHost(webView: store.webView(for: tab))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        }
        .onAppear { store.show(tab) }
    }

    private func toolbarButton(_ symbol: String, help: String, enabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
        .disabled(!enabled)
        .help(help)
    }
}

/// Hosts a long-lived web view. The web view belongs to `WebTabsStore`, not
/// to this view, so it moves into each new container (the grid view's window
/// is rebuilt every time it opens) with its page intact.
struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if webView.superview !== container { attach(to: container) }
    }

    private func attach(to container: NSView) {
        webView.removeFromSuperview()
        // The grid view is always dark; sites follow your system appearance.
        webView.appearance = NSApp.effectiveAppearance
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        // Keys go to the page (arrow keys, typing in chat boxes…).
        DispatchQueue.main.async { [weak webView] in
            guard let webView = webView else { return }
            webView.window?.makeFirstResponder(webView)
        }
    }
}
