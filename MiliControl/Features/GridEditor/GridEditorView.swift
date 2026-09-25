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
    /// Closes the editor and opens Mission Control (to reorder desktops).
    let openMissionControl: () -> Void
    let openSettings: () -> Void
}

struct GridEditorView: View {
    @ObservedObject var model: GridEditorModel
    @ObservedObject var desktops: DesktopStore
    @ObservedObject var layout: LayoutStore
    @ObservedObject var snapshots: DesktopSnapshots
    @ObservedObject var prefs: Preferences
    let dashboard: DashboardStore
    @ObservedObject var webTabs: WebTabsStore
    let screenSize: CGSize
    let actions: GridEditorActions
    let dashboardActions: DashboardActions

    private var tileSize: CGSize {
        let columns = CGFloat(max(layout.layout.rows.map(\.count).max() ?? 1, 1))
        let width = min(210, max(120, (screenSize.width - 200) / columns - 18))
        return CGSize(width: width, height: (width * 0.6).rounded())
    }

    /// A little taller than one row, never more than a quarter of the screen.
    private var dashboardHeight: CGFloat {
        let rowHeight = tileSize.height + 90       // tiles + labels + name + padding
        return min(max(rowHeight * 1.1, 170), 250, screenSize.height * 0.25).rounded()
    }

    /// The web tab on screen, or nil for the desktops.
    private var selectedTab: WebTab? {
        model.selectedTab.flatMap { id in prefs.webTabs.first { $0.id == id } }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VisualEffectBackground(material: .fullScreenUI)
                .overlay(Color.black.opacity(0.25))
                .ignoresSafeArea()

            if let tab = selectedTab {
                WebTabPage(store: webTabs, tab: tab)
                    .id(tab.id)
                    .padding(.top, 12)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                desktopsContent
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }

            if !prefs.webTabs.isEmpty {
                GridTabSwitcher(store: webTabs, tabs: prefs.webTabs, selected: $model.selectedTab)
                    .padding(.top, 12)
                    .padding(.trailing, 24)
            }
        }
        .onChange(of: model.selectedTab) { _ in webTabs.show(selectedTab) }
    }

    /// The desktops: header, dashboard, rows, bottom bar.
    private var desktopsContent: some View {
        ZStack {
            // Clicking empty space closes the editor, like Mission Control.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { actions.close() }

            VStack(spacing: 0) {
                header
                if DashboardView.hasPanels(prefs) {
                    DashboardView(store: dashboard, prefs: prefs,
                                  height: dashboardHeight, actions: dashboardActions)
                        .padding(.horizontal, 40)
                        .padding(.top, 8)
                        .zIndex(1)      // the calendar's hover bubble may overlap the rows
                }
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
                .overlay(alignment: .top) {
                    if model.showsOrderHint {
                        NativeOrderHint(openMissionControl: actions.openMissionControl,
                                        dismiss: { model.hideOrderHint() })
                            .padding(.top, 6)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
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
            Text(prefs.rowsFollowNativeOrder
                 ? "Drag desktops between rows · Order inside a row follows Mission Control · Click to go"
                 : "Drag desktops to arrange your rows · Click to go · ⌃⌥ + arrows to navigate")
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
        // Hidden slots (an app that's out of fullscreen) have no space: no tile.
        if let space = desktops.space(forKey: key) {
            TileView(number: space.number,
                     title: DesktopLabel.title(for: space, in: desktops),
                     apps: desktops.apps[key] ?? [],
                     snapshot: snapshots.isActive ? snapshots.images[key] : nil,
                     isCurrent: key == desktops.currentKey,
                     isSelected: key == model.selectedKey,
                     isReachable: space.number.map { SymbolicHotKeys.switchableDesktops.contains($0) } ?? true,
                     isSlow: space.number.map { model.slowDesktops.contains($0) } ?? false,
                     size: tileSize)
                .opacity(model.draggingKey == key ? 0.35 : 1)
                .onTapGesture { actions.go(key) }
                .onDrag {
                    model.draggingKey = key
                    model.dragOriginRow = layout.layout.position(of: key)?.row
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

    /// "9 desktops · 2 fullscreen apps · 3 rows"
    private var summary: String {
        var parts = ["\(desktops.desktops.count) desktops"]
        let fullscreen = desktops.fullscreens.count
        if fullscreen > 0 { parts.append("\(fullscreen) fullscreen app\(fullscreen == 1 ? "" : "s")") }
        parts.append("\(layout.layout.rows.count) rows")
        return parts.joined(separator: " · ")
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Text(summary)
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
    /// Desktop number; nil for a fullscreen app.
    let number: Int?
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
                    badge
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
            .overlay(alignment: .bottomTrailing) {
                ProfileBadges(profiles: profiles)
                    .padding(7)
            }
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

    /// Browser profiles of the windows on this desktop (up to three).
    private var profiles: [BrowserProfile] {
        var result: [BrowserProfile] = []
        for profile in apps.flatMap(\.profiles) where !result.contains(profile) {
            result.append(profile)
        }
        return Array(result.prefix(3))
    }

    /// The desktop number, or a fullscreen symbol.
    @ViewBuilder
    private var badge: some View {
        if let number = number {
            Text("\(number)")
        } else {
            Label("Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right")
                .labelStyle(.iconOnly)
        }
    }

    private var helpText: String {
        guard let number = number else { return "Click to go to \(title) (fullscreen)" }
        if !isReachable { return "macOS can't switch to this desktop" }
        if isSlow {
            return "Click to go to Desktop \(number). Assign it a shortcut in MiliControl Settings for one instant slide."
        }
        return "Click to go to Desktop \(number)"
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

// MARK: - Native order hint

/// Explains why a desktop didn't move within its row, with a shortcut to
/// the place where that order is changed.
private struct NativeOrderHint: View {
    let openMissionControl: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("The order inside a row follows macOS")
                    .font(.system(size: 13, weight: .semibold))
                Text("That keeps every slide going the way you move. To reorder, drag the desktop in Mission Control's top bar — MiliControl updates by itself.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 440, alignment: .leading)
            Button("Open Mission Control", action: openMissionControl)
                .buttonStyle(.borderedProminent)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.16))
                .onTapGesture {}                    // clicks here never close the editor
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
    }
}

// MARK: - Browser profile badges

/// Overlapping round avatars — the profile picture, or its initial on the
/// profile's colour — like the avatar in Chrome's toolbar.
private struct ProfileBadges: View {
    let profiles: [BrowserProfile]

    var body: some View {
        HStack(spacing: -6) {
            ForEach(profiles) { profile in
                avatar(profile)
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .help(profile.name)
            }
        }
    }

    @ViewBuilder
    private func avatar(_ profile: BrowserProfile) -> some View {
        if let picture = profile.picture {
            Image(nsImage: picture)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Circle().fill(Color(nsColor: profile.color ?? .systemGray))
                Text(profile.initial)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Drag & drop

/// Dragging over a tile moves the dragged desktop into that tile's slot.
/// With native order on, only moves to another row happen (the desktop then
/// takes its numbered place there); reordering within its own row shows a
/// hint pointing to Mission Control instead.
private struct TileDropDelegate: DropDelegate {
    let key: String
    let layout: LayoutStore
    let model: GridEditorModel

    func dropEntered(info: DropInfo) {
        guard let dragging = model.draggingKey, dragging != key,
              let target = layout.layout.position(of: key),
              let from = layout.layout.position(of: dragging) else { return }
        if layout.followsNativeOrder && from.row == target.row {
            // Just passing over neighbours after a move into this row is fine;
            // trying to reorder the row the drag started in gets the hint.
            if model.dragOriginRow == target.row { model.showOrderHint() }
            return
        }
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
