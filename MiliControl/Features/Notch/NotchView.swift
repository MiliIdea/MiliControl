//
//  NotchView.swift
//  MiliControl
//
//  The now-playing player that grows out of the notch.
//
//    compact  — the notch widens a little: artwork on the left, a small
//               wave on the right that moves with the music.
//    expanded — on hover it opens downward: artwork, title and artist,
//               progress, and previous / play-pause / next.
//    peek     — a new Telegram / WhatsApp / Slack message drops down for a
//               few seconds: app icon, sender, preview. Click to open it.
//    inbox    — while the grid editor is open: one chip per messaging app
//               with unread messages, in the notch's left wing (left of the
//               music, if it's playing), at the notch's own height; the notch
//               widens evenly on both sides. Hover a
//               chip and the notch opens downward with its latest messages;
//               click to go to the app.
//
//  The black shape continues the notch itself (flat top, soft inward top
//  corners, rounded bottom), so it reads as the notch stretching, not as a
//  window on top of it.
//

import SwiftUI
import AppKit

final class NotchModel: ObservableObject {
    enum State: Equatable { case hidden, compact, expanded, peek, inbox }

    @Published var state: State = .hidden
    /// The message shown in the `.peek` state.
    @Published var peek: CapturedMessage?
    /// The inbox chip under the pointer, and how many message rows it opens.
    @Published private(set) var hoveredApp: MessagingApp?
    @Published private(set) var inboxRows = 0

    /// Inbox chips in the left wing, and whether the music sits beside them.
    @Published var inboxChips = 0
    @Published var inboxWithMusic = false

    /// Rows shown for an app's latest messages (at least one: the summary).
    static let maxInboxRows = 3
    private static let inboxRowHeight: CGFloat = 38
    static let chipWidth: CGFloat = 52

    /// Inbox wing: chips (+ artwork) on the left; the right wing mirrors its
    /// width so the notch widens evenly on both sides.
    var inboxWing: CGFloat { CGFloat(inboxChips) * Self.chipWidth + 8 + (inboxWithMusic ? wing : 0) }
    /// Width of the notch-height strip in the inbox.
    var inboxStrip: CGFloat { notch.width + inboxWing * 2 }

    func hover(_ app: MessagingApp?, messageCount: Int) {
        hoveredApp = app
        inboxRows = app == nil ? 0 : max(1, min(Self.maxInboxRows, messageCount))
    }
    /// The notch (or, without one, a menu-bar-height pill slot).
    @Published var notch = CGSize(width: 200, height: 32)
    @Published var hasNotch = true

    /// Width of each side "wing" in compact state.
    var wing: CGFloat { notch.height + 10 }

    func size(for state: State) -> CGSize {
        switch state {
        case .hidden:
            return CGSize(width: hasNotch ? notch.width : 0, height: notch.height)
        case .compact:
            return CGSize(width: notch.width + wing * 2, height: notch.height)
        case .expanded:
            return CGSize(width: max(notch.width + 190, 380), height: notch.height + 132)
        case .peek:
            return CGSize(width: max(notch.width + 170, 360), height: notch.height + 62)
        case .inbox:
            guard inboxRows > 0 else { return CGSize(width: inboxStrip, height: notch.height) }
            return CGSize(width: max(inboxStrip, 340),
                          height: notch.height + CGFloat(inboxRows) * Self.inboxRowHeight + 12)
        }
    }

    /// Room the window needs for the largest state (plus its shadow).
    var canvas: CGSize {
        let expanded = size(for: .expanded)
        // Widest inbox: three chips plus music, on both sides.
        let inboxWidth = notch.width + 2 * (3 * Self.chipWidth + 8 + wing)
        let inboxHeight = notch.height + CGFloat(Self.maxInboxRows) * Self.inboxRowHeight + 12
        return CGSize(width: max(expanded.width, inboxWidth, 340) + 40,
                      height: max(expanded.height, inboxHeight) + 30)
    }
}

struct NotchActions {
    let playPause: () -> Void
    let next: () -> Void
    let previous: () -> Void
    let openPlayer: () -> Void
    let openMessage: (CapturedMessage) -> Void
    /// Go to a messaging app (closes the grid editor first).
    let openApp: (MessagingApp) -> Void
}

struct NotchView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var messages: MessageMonitor
    let actions: NotchActions

    private var size: CGSize { model.size(for: model.state) }
    private var tint: Color { nowPlaying.tint.map(Color.init(nsColor:)) ?? .white }


    private var shape: NotchShape {
        let open = model.state == .expanded || model.state == .peek
            || (model.state == .inbox && model.inboxRows > 0)
        return NotchShape(topCornerRadius: open ? 10 : 6, bottomCornerRadius: open ? 24 : 10)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape
                    .fill(Color.black)
                    .frame(width: size.width, height: size.height)

                switch model.state {
                case .hidden:
                    EmptyView()
                case .compact:
                    compact.transition(.opacity)
                case .expanded:
                    expanded.transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                case .peek:
                    if let message = model.peek {
                        peek(message)
                            .id(message.id)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                case .inbox:
                    inbox.transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            .shadow(color: .black.opacity(model.state == .expanded || model.inboxRows > 0 ? 0.45 : 0),
                    radius: 14, y: 6)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.state)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.inboxRows)
        .animation(.easeInOut(duration: 0.3), value: nowPlaying.track?.id)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Compact

    private var compact: some View {
        let art = model.notch.height - 12
        return HStack(spacing: 0) {
            Artwork(image: nowPlaying.artwork, size: art, radius: 5)
                .frame(width: model.wing, height: model.notch.height)
                .id(nowPlaying.track?.id)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            Spacer(minLength: 0)
            Wave(playing: nowPlaying.isPlaying, tint: tint, height: art * 0.75)
                .frame(width: model.wing, height: model.notch.height)
        }
        .frame(width: size.width, height: model.notch.height)
    }

    // MARK: - Inbox (grid editor open)

    private var unreadApps: [MessagingApp] {
        MessagingApp.allCases.filter { messages.badges[$0] != nil }
    }

    private var inbox: some View {
        VStack(spacing: 8) {
            // The notch-height strip, even on both sides:
            //   [chips][artwork]  notch  [wave]  ·····
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ForEach(unreadApps) { app in
                        InboxChip(app: app, badge: messages.badges[app] ?? "",
                                  isHovered: model.hoveredApp == app, height: model.notch.height - 10)
                            .frame(width: NotchModel.chipWidth)
                            .onHover { inside in
                                guard inside else { return }
                                model.hover(app, messageCount: messages.messages.filter { $0.app == app }.count)
                            }
                            .onTapGesture { actions.openApp(app) }
                            .help("Open \(app.name)")
                    }
                    if model.inboxWithMusic {
                        Artwork(image: nowPlaying.artwork, size: model.notch.height - 12, radius: 5)
                            .frame(width: model.wing, height: model.notch.height)
                            .onTapGesture(perform: actions.openPlayer)
                    }
                }
                .frame(width: model.inboxWing)
                Spacer(minLength: model.notch.width)
                HStack(spacing: 0) {
                    if model.inboxWithMusic {
                        Wave(playing: nowPlaying.isPlaying, tint: tint,
                             height: (model.notch.height - 12) * 0.75)
                            .frame(width: model.wing, height: model.notch.height)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: model.inboxWing)
            }
            .frame(width: model.inboxStrip, height: model.notch.height)

            if let app = model.hoveredApp {
                InboxDetail(app: app, badge: messages.badges[app] ?? "",
                            messages: Array(messages.messages.filter { $0.app == app }.prefix(NotchModel.maxInboxRows)),
                            open: { actions.openApp(app) })
                    .padding(.horizontal, 12)
                    .id(app)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: size.width, alignment: .top)
        .animation(.easeOut(duration: 0.18), value: model.hoveredApp)
    }

    // MARK: - Message peek

    private func peek(_ message: CapturedMessage) -> some View {
        Button { actions.openMessage(message) } label: {
            HStack(spacing: 12) {
                Group {
                    if let icon = message.app.icon {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "message.fill").foregroundStyle(.white)
                    }
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(message.sender)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(message.app.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Text(message.text)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(message.app.name)")
        .padding(.horizontal, 18)
        .padding(.top, model.notch.height + 8)
        .padding(.bottom, 12)
        .frame(width: size.width, alignment: .top)
    }

    // MARK: - Expanded

    private var expanded: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: actions.openPlayer) {
                    Artwork(image: nowPlaying.artwork, size: 56, radius: 12)
                }
                .buttonStyle(.plain)
                .help("Open \(nowPlaying.player?.scriptName ?? "player")")
                .id(nowPlaying.track?.id)
                .transition(.scale(scale: 0.8).combined(with: .opacity))

                VStack(alignment: .leading, spacing: 3) {
                    Text(nowPlaying.track?.title ?? "")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(nowPlaying.track?.artist ?? "")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                Wave(playing: nowPlaying.isPlaying, tint: tint, height: 20)
            }

            Progress(nowPlaying: nowPlaying, tint: tint)

            HStack(spacing: 34) {
                ControlButton(symbol: "backward.fill", size: 15, action: actions.previous)
                ControlButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 22,
                              action: actions.playPause)
                ControlButton(symbol: "forward.fill", size: 15, action: actions.next)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, model.notch.height + 8)
        .padding(.bottom, 14)
        .frame(width: size.width, alignment: .top)
    }
}

// MARK: - Pieces

/// An app's icon with its unread badge.
private struct InboxChip: View {
    let app: MessagingApp
    let badge: String
    let isHovered: Bool
    let height: CGFloat

    var body: some View {
        HStack(spacing: 5) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: height - 6, height: height - 6)
            }
            Text(badge.contains(where: \.isNumber) ? badge : "•")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 6)
        .frame(height: height)
        .background(Capsule().fill(Color.white.opacity(isHovered ? 0.2 : 0.1)))
        .scaleEffect(isHovered ? 1.06 : 1)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contentShape(Capsule())
    }
}

/// The latest messages of one app (or a summary when none were caught).
private struct InboxDetail: View {
    let app: MessagingApp
    let badge: String
    let messages: [CapturedMessage]
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if messages.isEmpty {
                row(title: app.name,
                    text: badge.contains(where: \.isNumber) ? "\(badge) unread — click to open" : "Unread — click to open",
                    date: nil)
            } else {
                ForEach(messages) { message in
                    row(title: message.sender, text: message.text, date: message.date)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }

    private func row(title: String, text: String, date: Date?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .lineLimit(1)
            Spacer(minLength: 6)
            if let date = date {
                Text(date, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
        }
        .frame(height: 34)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

private struct Artwork: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Thin bars in the artwork's colour that fade out at both ends. Lively
/// while playing (each bar dances on its own over a steady pulse); paused,
/// they rest as small dots. Purely animated — MiliControl never listens to
/// the audio, so macOS shows no screen-sharing indicator for it.
private struct Wave: View {
    let playing: Bool
    let tint: Color
    let height: CGFloat

    private static let bars = 7
    private let barWidth: CGFloat = 2
    private let spacing: CGFloat = 2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 45, paused: !playing)) { context in
            let values = currentLevels(at: context.date.timeIntervalSinceReferenceDate)
            HStack(alignment: .center, spacing: spacing) {
                ForEach(values.indices, id: \.self) { index in
                    Capsule()
                        .fill(tint)
                        .frame(width: barWidth, height: max(barWidth, values[index] * height))
                }
            }
            .frame(height: height)
            .animation(.easeOut(duration: 0.12), value: values)
        }
        // Soft fade into the black at the left and right ends.
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                     .init(color: .black, location: 0.3),
                                     .init(color: .black, location: 0.7),
                                     .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .opacity(playing ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.4), value: playing)
    }

    private func currentLevels(at time: TimeInterval) -> [CGFloat] {
        guard playing else { return Array(repeating: 0, count: Self.bars) }   // dots
        // Quick, independent jitter per bar over a steady pulse.
        let pulse = pow(max(0, sin(time * .pi * 2 * 2.1)), 4)
        return (0 ..< Self.bars).map { index in
            let i = Double(index)
            let fast = sin(time * (9.0 + i * 1.7) + i * 2.3)
            let slow = sin(time * (4.1 + i * 0.9) + i * 0.7)
            let value = 0.45 + 0.25 * fast * slow + 0.2 * abs(slow) + 0.15 * pulse
            return CGFloat(min(1, max(0.12, value)))
        }
    }
}

private struct Progress: View {
    @ObservedObject var nowPlaying: NowPlaying
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = nowPlaying.track?.duration ?? 0
            let position = nowPlaying.currentPosition(at: context.date)
            let fraction = duration > 0 ? min(1, max(0, position / duration)) : 0
            HStack(spacing: 8) {
                Text(Self.format(position))
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(tint).frame(width: geometry.size.width * fraction)
                    }
                }
                .frame(height: 4)
                Text(duration > 0 ? Self.format(duration) : "--:--")
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
            .animation(.linear(duration: 0.5), value: fraction)
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
                .scaleEffect(hovering ? 1.1 : 1)
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Flat top edge with small inward curves at the top corners (so it melts
/// into the menu bar like the notch does) and rounded bottom corners.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set { topCornerRadius = newValue.first; bottomCornerRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topCornerRadius, rect.width / 4, rect.height / 2)
        let bottom = min(bottomCornerRadius, (rect.width - 2 * top) / 2, rect.height - top)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Top-left inward curve.
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                          control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
                          control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
                          control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        // Top-right inward curve.
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
