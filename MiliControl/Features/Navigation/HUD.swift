//
//  HUD.swift
//  MiliControl
//
//  The navigation grid shown while you hold an arrow: a map of your rows with
//  the destination highlighted, like the ⌘-Tab switcher. It never takes
//  focus, so the app you're in stays active.
//
//  Two looks:
//    • icons    — compact tiles with each desktop's main app icon;
//    • previews — larger tiles showing how each desktop looked when you were
//                 last on it (DesktopSnapshots). Desktops without a snapshot
//                 yet fall back to their app icon.
//

import SwiftUI
import AppKit

struct HUDCell: Identifiable, Equatable {
    let key: String
    let number: Int
    let pid: pid_t?
    let title: String
    let snapshot: NSImage?
    var id: String { key }
}

struct HUDRow: Identifiable, Equatable {
    /// Index of the row in the grid layout.
    let id: Int
    let name: String
    let cells: [HUDCell]
}

final class HUDModel: ObservableObject {
    @Published var rows: [HUDRow] = []
    @Published var targetKey: String?
    @Published var currentKey: String?
    @Published var message: String?
    @Published var usesPreviews = false
    @Published var cellSize = HUDMetrics.iconCell

    var targetTitle: String {
        rows.flatMap(\.cells).first { $0.key == targetKey }?.title ?? ""
    }
}

enum HUDMetrics {
    static let iconCell = CGSize(width: 58, height: 40)
    static let maxPreviewWidth: CGFloat = 150
    static let minPreviewWidth: CGFloat = 90
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 16
    static let captionHeight: CGFloat = 26
    /// Width of the row-name column on the left.
    static let nameWidth: CGFloat = 96
    static let minWidth: CGFloat = 220
    static let messageSize = CGSize(width: 420, height: 64)

    /// Tile size: fixed for icons; for previews, the screen's shape, as large
    /// as fits comfortably on screen for the widest row.
    static func cellSize(previews: Bool, columns: Int, screen: NSScreen?) -> CGSize {
        guard previews else { return iconCell }
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let aspect = frame.width / max(frame.height, 1)
        let available = frame.width * 0.8 - nameWidth - padding * 2
        let columnCount = CGFloat(max(columns, 1))
        let fit = (available - (columnCount - 1) * spacing) / columnCount
        let width = max(minPreviewWidth, min(maxPreviewWidth, fit)).rounded()
        return CGSize(width: width, height: (width / aspect).rounded())
    }

    static func panelSize(rows: [HUDRow], cell: CGSize) -> CGSize {
        let columns = rows.map(\.cells.count).max() ?? 1
        let rowCount = max(rows.count, 1)
        let width = nameWidth + spacing
            + CGFloat(columns) * cell.width + CGFloat(max(columns - 1, 0)) * spacing
            + padding * 2
        let height = CGFloat(rowCount) * cell.height + CGFloat(rowCount - 1) * spacing
            + padding * 2 + captionHeight
        return CGSize(width: max(width, minWidth), height: height)
    }
}

struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow)
            if let message = model.message {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18)
            } else {
                VStack(spacing: HUDMetrics.spacing) {
                    ForEach(model.rows) { row in
                        HStack(spacing: HUDMetrics.spacing) {
                            rowName(row)
                            ForEach(row.cells) { cell($0) }
                            Spacer(minLength: 0)
                        }
                    }
                    Text(model.targetTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .frame(height: HUDMetrics.captionHeight - HUDMetrics.spacing, alignment: .bottom)
                }
                .padding(HUDMetrics.padding)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Row name on the left; the destination's row stands out.
    private func rowName(_ row: HUDRow) -> some View {
        let isTargetRow = row.cells.contains { $0.key == model.targetKey }
        return Text(row.name)
            .font(.system(size: 12, weight: isTargetRow ? .bold : .medium))
            .foregroundStyle(isTargetRow ? Color.primary : Color.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: HUDMetrics.nameWidth, alignment: .trailing)
            .animation(.easeOut(duration: 0.12), value: isTargetRow)
    }

    private func cell(_ cell: HUDCell) -> some View {
        let isTarget = cell.key == model.targetKey
        let isCurrent = cell.key == model.currentKey
        let size = model.cellSize
        let shape = RoundedRectangle(cornerRadius: model.usesPreviews ? 6 : 8, style: .continuous)

        return ZStack(alignment: .topLeading) {
            if model.usesPreviews, let snapshot = cell.snapshot {
                Image(nsImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                // Icon tile (also the fallback for a desktop not seen yet).
                shape.fill(isTarget && !model.usesPreviews ? Color.accentColor : Color.primary.opacity(0.10))
                appIcon(cell, highlighted: isTarget && !model.usesPreviews)
                    .frame(width: size.width, height: size.height)
            }
            numberBadge(cell.number, onPreview: model.usesPreviews,
                        highlighted: isTarget && !model.usesPreviews)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(borderColor(isTarget: isTarget, isCurrent: isCurrent),
                                    lineWidth: isTarget && model.usesPreviews ? 3 : 1.5))
        .shadow(color: isTarget && model.usesPreviews ? Color.accentColor.opacity(0.6) : .clear,
                radius: 6)
        .animation(.easeOut(duration: 0.12), value: isTarget)
    }

    private func borderColor(isTarget: Bool, isCurrent: Bool) -> Color {
        if isTarget { return model.usesPreviews ? Color.accentColor : .clear }
        return isCurrent ? Color.primary.opacity(0.55) : .clear
    }

    @ViewBuilder
    private func appIcon(_ cell: HUDCell, highlighted: Bool) -> some View {
        let iconSize = min(model.cellSize.height * 0.55, 30)
        if let pid = cell.pid, let icon = IconCache.shared.icon(for: pid) {
            Image(nsImage: icon).resizable().frame(width: iconSize, height: iconSize)
        } else {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 14))
                .foregroundStyle(highlighted ? Color.white : Color.secondary)
        }
    }

    private func numberBadge(_ number: Int, onPreview: Bool, highlighted: Bool) -> some View {
        Text("\(number)")
            .font(.system(size: 9, weight: .bold).monospacedDigit())
            .foregroundStyle(onPreview || highlighted ? Color.white : Color.secondary)
            .padding(.horizontal, onPreview ? 5 : 0)
            .padding(.vertical, onPreview ? 1 : 0)
            .background(Capsule().fill(onPreview ? Color.black.opacity(0.5) : .clear))
            .padding(4)
    }
}

final class HUDController {

    let model = HUDModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    /// Bumped on every show, so a fade-out that finishes late can't hide a
    /// HUD that was re-shown in the meantime.
    private var generation = 0

    /// True while the HUD is on screen.
    var isVisible: Bool { (panel?.isVisible ?? false) && (panel?.alphaValue ?? 0) > 0 }

    /// Shows (or updates) the grid.
    func show() {
        model.message = nil
        present(size: HUDMetrics.panelSize(rows: model.rows, cell: model.cellSize))
    }

    /// Shows a short message, then hides by itself.
    func flash(_ message: String, duration: TimeInterval = 2.6) {
        model.message = message
        present(size: HUDMetrics.messageSize)
        hide(after: duration)
    }

    /// Removes the HUD at once, with no fade — used right before a switch so
    /// it vanishes on the desktop you're leaving instead of riding along with
    /// the slide.
    func hideImmediately() {
        hideWork?.cancel()
        hideWork = nil
        generation += 1                      // cancels any fade still finishing
        guard let panel = panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 0
        }
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    func hide(after delay: TimeInterval = 0) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let panel = self.panel else { return }
            let expected = self.generation
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                // Only order out if nothing re-showed it meanwhile.
                if self?.generation == expected { panel.orderOut(nil) }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func present(size: CGSize) {
        hideWork?.cancel()
        generation += 1
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let screen = NSScreen.main ?? NSScreen.screens.first
        if let frame = screen?.visibleFrame {
            let origin = CGPoint(x: frame.midX - size.width / 2,
                                 y: frame.midY - size.height / 2)
            panel.setFrame(CGRect(origin: origin, size: size), display: true)
        }
        // A new animator transaction on alphaValue replaces any fade-out still
        // running; the direct set makes it immediate. The generation check in
        // hide() keeps a late completion from ordering the panel out.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Appears on whichever desktop is active when shown, but doesn't follow
        // you to other desktops — so it can never flash on the destination.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let hosting = NSHostingView(rootView: HUDView(model: model))
        hosting.sizingOptions = []          // we size the panel ourselves
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }
}
