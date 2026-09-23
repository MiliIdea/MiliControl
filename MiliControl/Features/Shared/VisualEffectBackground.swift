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
    static func title(for key: String, number: Int, in store: DesktopStore) -> String {
        store.title(forKey: key) ?? "Desktop \(number)"
    }
}
