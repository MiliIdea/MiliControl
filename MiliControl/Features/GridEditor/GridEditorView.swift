//
//  GridEditorView.swift
//  MiliControl
//
//  SwiftUI content of the full-screen grid editor.
//
//  Drag & drop: dragging a tile over another tile moves it into that slot
//  (live, across rows); dragging over a row's empty area appends it to that
//  row. The layout is saved as you go.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GridEditorActions {
    let go: (String) -> Void
    let close: () -> Void
    let addRow: () -> Void
    let removeRow: (Int) -> Void
    let reset: () -> Void
    let openSettings: () -> Void
}

struct GridEditorView: View {
    @ObservedObject var model: GridEditorModel
    @ObservedObject var desktops: DesktopStore
    @ObservedObject var layout: LayoutStore
    @ObservedObject var snapshots: DesktopSnapshots
    let screenWidth: CGFloat
    let actions: GridEditorActions

    private var tileSize: CGSize {
        let columns = CGFloat(max(layout.layout.rows.map(\.count).max() ?? 1, 1))
        let width = min(210, max(120, (screenWidth - 200) / columns - 18))
        return CGSize(width: width, height: (width * 0.6).rounded())
    }

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .fullScreenUI)
                .overlay(Color.black.opacity(0.25))
                .ignoresSafeArea()
            // Clicking empty space closes the editor, like Mission Control.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { actions.close() }

            VStack(spacing: 0) {
                header
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 22) {
                        ForEach(Array(layout.layout.rows.enumerated()), id: \.offset) { index, keys in
                            row(index: index, keys: keys)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                    // Empty space inside the scroll area also closes the editor.
                    .contentShape(Rectangle())
                    .onTapGesture { actions.close() }
                }
                bottomBar
            }
        }
        // A drop that lands on no target still ends the drag cleanly.
        .onDrop(of: [UTType.text], delegate: EndDragDelegate(model: model))
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 6) {
            Text("MiliControl")
                .font(.system(size: 22, weight: .semibold))
            Text("Drag desktops to arrange your rows · Click to go · ⌃⌥ + arrows to navigate")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 48)
        .padding(.bottom, 8)
    }

    private func row(index: Int, keys: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Row \(index + 1)", text: nameBinding(for: index))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: 240)
                    .onSubmit { NSApp.keyWindow?.makeFirstResponder(nil) }   // Return finishes editing
                    .help("Name this row. The name also shows in the navigation grid.")
                Spacer()
                if layout.layout.rows.count > 1 {
                    Button { actions.removeRow(index) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove this row. Its desktops move to the row above.")
                }
            }

            HStack(spacing: 16) {
                ForEach(keys, id: \.self) { key in
                    tile(for: key)
                }
                if keys.isEmpty {
                    emptyRowPlaceholder
                }
            }
            .frame(minHeight: tileSize.height + 26, alignment: .leading)
        }
        .padding(16)
        .frame(minWidth: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
                // Clicks on a row's empty space shouldn't close the editor, and
                // clicking there ends name editing. Lives in the background (not
                // on the row itself) so it never steals clicks from the name field.
                .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
        )
        .onDrop(of: [UTType.text],
                delegate: RowDropDelegate(row: index, layout: layout, model: model))
    }

    private func nameBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { layout.layout.rawName(ofRow: index) },
            set: { name in layout.update { $0.renameRow(index, to: name) } })
    }

    @ViewBuilder
    private func tile(for key: String) -> some View {
        if let desktop = desktops.desktop(forKey: key) {
            TileView(desktop: desktop,
                     title: DesktopLabel.title(for: key, number: desktop.number, in: desktops),
                     apps: desktops.apps[key] ?? [],
                     snapshot: snapshots.isActive ? snapshots.images[key] : nil,
                     isCurrent: key == desktops.currentKey,
                     isSelected: key == model.selectedKey,
                     isReachable: SymbolicHotKeys.switchableDesktops.contains(desktop.number),
                     isSlow: model.slowDesktops.contains(desktop.number),
                     size: tileSize)
                .opacity(model.draggingKey == key ? 0.35 : 1)
                .onTapGesture { actions.go(key) }
                .onDrag {
                    model.draggingKey = key
                    return NSItemProvider(object: key as NSString)
                }
                .onDrop(of: [UTType.text],
                        delegate: TileDropDelegate(key: key, layout: layout, model: model))
        }
    }

    private var emptyRowPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .frame(width: tileSize.width, height: tileSize.height)
            .overlay(
                Text("Drag desktops here")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            )
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Text("\(desktops.desktops.count) desktops · \(layout.layout.rows.count) rows")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Reset Layout…") { actions.reset() }
            Button("Settings…") { actions.openSettings() }
            Button { actions.addRow() } label: {
                Label("Add Row", systemImage: "plus")
            }
            Button("Done") { actions.close() }
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.25))
    }
}

// MARK: - Tile

private struct TileView: View {
    let desktop: Desktop
    let title: String
    let apps: [AppSummary]
    let snapshot: NSImage?
    let isCurrent: Bool
    let isSelected: Bool
    let isReachable: Bool
    /// Reachable, but only in several slides (no direct shortcut yet).
    let isSlow: Bool
    let size: CGSize

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.09))

                if let snapshot = snapshot {
                    // How this desktop looked when you were last on it.
                    Image(nsImage: snapshot)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else {
                    icons
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack {
                    Text("\(desktop.number)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                    Spacer()
                    if isCurrent {
                        Text("Current")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor))
                    }
                }
                .foregroundStyle(.white)
                .padding(8)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.18),
                                  lineWidth: isSelected ? 3 : 1)
            )
            .shadow(color: .black.opacity(isSelected ? 0.45 : 0.2), radius: isSelected ? 10 : 4, y: 3)
            .scaleEffect(isSelected ? 1.03 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)

            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !isReachable {
                    Text("Can't be reached — macOS supports 1–16")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else if isSlow {
                    Label("No shortcut — takes a few slides", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: size.width)
        }
        .opacity(isReachable ? 1 : 0.5)
        .contentShape(Rectangle())
        .help(helpText)
    }

    private var helpText: String {
        if !isReachable { return "macOS can't switch to this desktop" }
        if isSlow {
            return "Click to go to Desktop \(desktop.number). Assign it a shortcut in MiliControl Settings for one instant slide."
        }
        return "Click to go to Desktop \(desktop.number)"
    }

    @ViewBuilder
    private var icons: some View {
        let iconSize = min(34, size.height * 0.32)
        if apps.isEmpty {
            Text("Empty")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                ForEach(apps.prefix(4)) { app in
                    if let icon = IconCache.shared.icon(for: app.pid) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: iconSize, height: iconSize)
                    }
                }
            }
        }
    }
}

// MARK: - Drag & drop

/// Dragging over a tile moves the dragged desktop into that tile's slot.
private struct TileDropDelegate: DropDelegate {
    let key: String
    let layout: LayoutStore
    let model: GridEditorModel

    func dropEntered(info: DropInfo) {
        guard let dragging = model.draggingKey, dragging != key,
              let target = layout.layout.position(of: key) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            layout.update { $0.move(dragging, toRow: target.row, index: target.column) }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        model.draggingKey = nil
        return true
    }
}

/// Dragging over a row's empty area appends the desktop to that row.
private struct RowDropDelegate: DropDelegate {
    let row: Int
    let layout: LayoutStore
    let model: GridEditorModel

    func dropEntered(info: DropInfo) {
        guard let dragging = model.draggingKey,
              let from = layout.layout.position(of: dragging),
              from.row != row else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            layout.update { $0.move(dragging, toRow: row, index: .max) }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        model.draggingKey = nil
        return true
    }
}

private struct EndDragDelegate: DropDelegate {
    let model: GridEditorModel

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        model.draggingKey = nil
        return true
    }
}
