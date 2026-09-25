//
//  VisualEffectBackground.swift
//  MiliControl
//
//  Native macOS vibrancy (NSVisualEffectView) for SwiftUI views hosted in
//  borderless windows, so the HUD and grid editor blur what's behind them
//  exactly like system overlays do.
//

import SwiftUI
import AppKit

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// Tile/cell label helpers shared by the HUD and the editor.
enum DesktopLabel {
    /// What's on it ("Google Chrome · Work", "Safari +2"), else its own name.
    static func title(for space: GridSpace, in store: DesktopStore) -> String {
        if let title = store.title(forKey: space.key) { return title }
        switch space {
        case .desktop(let desktop): return "Desktop \(desktop.number)"
        case .fullscreen(let fullscreen): return fullscreen.title
        }
    }
}
