//
//  NotchController.swift
//  MiliControl
//
//  Owns the notch player window: when it shows and how it follows the pointer.
//
//    • Shows while Spotify or Music is playing (and for a little while after
//      pausing), grows out of the notch, shrinks back into it when done.
//    • Pointer over it → expands; pointer leaves → collapses. The window
//      lets clicks through everywhere except the visible player, so it never
//      blocks the menu bar.
//    • Stays on top of the grid editor too (it sits one level above it), and
//      hands keyboard focus back to the editor after you use its buttons.
//    • A new Telegram / WhatsApp / Slack message drops down from the notch
//      for a few seconds (longer while the pointer is on it), then the notch
//      goes back to the player — or away, if nothing is playing.
//    • While the grid editor is open, the notch's left wing shows one chip per
//      messaging app with unread messages (left of the music, if playing), at
//      the notch's own height; hover one and the notch opens downward with
//      its latest messages, click to go to the app.
//    • Macs without a notch get the same player as a small pill at the top
//      centre of the main screen.
//

import AppKit
import Combine
import SwiftUI

/// Borderless and never activating, but able to take clicks for the buttons.
private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class NotchController {

    let model = NotchModel()

    private let nowPlaying: NowPlaying
    private let prefs: Preferences
    private let messages: MessageMonitor
    /// Goes to a messaging app (the app delegate closes the grid editor first).
    private let openApp: (MessagingApp) -> Void
    /// Set by the grid editor; the notch shows the inbox while it's open.
    var editorVisible = false {
        didSet { if editorVisible != oldValue { update() } }
    }

    private var panel: NotchPanel?
    private var screen: NSScreen?
    private var pointerTimer: Timer?
    private var hideWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var peekEndWork: DispatchWorkItem?
    private var pausedSince: Date?
    /// The window that had keyboard focus before the player opened (e.g. the
    /// grid editor); it gets focus back when the player folds up.
    private weak var keyWindowBeforeExpanding: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    /// How long the player stays after pausing.
    private static let pausedLinger: TimeInterval = 20
    /// How long a message peek stays (after the pointer leaves it).
    private static let peekDuration: TimeInterval = 4.5

    init(nowPlaying: NowPlaying, prefs: Preferences, messages: MessageMonitor,
         openApp: @escaping (MessagingApp) -> Void) {
        self.nowPlaying = nowPlaying
        self.prefs = prefs
        self.messages = messages
        self.openApp = openApp
    }

    func start() {
        prefs.$notchPlayer
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled { self.nowPlaying.start() } else { self.nowPlaying.stop() }
                self.update()
            }
            .store(in: &cancellables)

        nowPlaying.$track.map { _ in () }
            .merge(with: nowPlaying.$isPlaying.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.update() }
            .store(in: &cancellables)

        // Unread apps appearing or clearing (the inbox follows them).
        messages.$badges.map { _ in () }
            .merge(with: prefs.$notchInbox.map { _ in () }, prefs.$messagesEnabled.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.update() }
            .store(in: &cancellables)

        messages.newMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                guard let self = self, self.prefs.messagesEnabled, self.prefs.notchMessages else { return }
                self.showPeek(message)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)
    }

    /// Re-evaluates visibility (also after MiliControl's windows were hidden).
    func update() {
        let track = nowPlaying.track
        if nowPlaying.isPlaying { pausedSince = nil }
        else if track != nil, pausedSince == nil { pausedSince = Date() }

        let wanted = playerWanted
        if wanted || model.peek != nil || inboxWanted { show() } else { hide() }
        let resting: [NotchModel.State] = [.compact, .expanded, .inbox]
        if resting.contains(model.state) { settleState() }

        // Re-check when the pause grace period runs out.
        if wanted, !nowPlaying.isPlaying, let since = pausedSince {
            let remaining = Self.pausedLinger - Date().timeIntervalSince(since)
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, remaining + 0.05)) { [weak self] in
                self?.update()
            }
        }
    }

    /// The inbox shows while the grid editor is open and something is unread.
    private var inboxWanted: Bool {
        editorVisible && prefs.messagesEnabled && prefs.notchInbox && !messages.badges.isEmpty
    }

    /// Puts the notch in the state it should rest in: the inbox, else the
    /// player (unless it's open under the pointer).
    private func settleState() {
        // What the inbox strip holds right now.
        let chips = MessagingApp.allCases.filter { messages.badges[$0] != nil }.count
        if model.inboxChips != chips { model.inboxChips = chips }
        if model.inboxWithMusic != playerWanted { model.inboxWithMusic = playerWanted }

        if inboxWanted {
            if model.state != .inbox {
                model.hover(nil, messageCount: 0)
                model.state = .inbox
                panel?.ignoresMouseEvents = true           // until the pointer is on it
            }
        } else if model.state == .inbox {
            model.hover(nil, messageCount: 0)
            if playerWanted {
                model.state = .compact
                panel?.ignoresMouseEvents = true
            } else {
                hide()
            }
        }
    }

    /// Whether the music player should be up.
    private var playerWanted: Bool {
        let lingering = pausedSince.map { Date().timeIntervalSince($0) < Self.pausedLinger } ?? true
        return prefs.notchPlayer && nowPlaying.track != nil && (nowPlaying.isPlaying || lingering)
    }

    // MARK: - Message peek

    private func showPeek(_ message: CapturedMessage) {
        model.peek = message
        show()
        model.state = .peek
        panel?.ignoresMouseEvents = false                 // click it to open the chat's app
        schedulePeekEnd(after: Self.peekDuration)
    }

    private func schedulePeekEnd(after delay: TimeInterval) {
        peekEndWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.endPeek() }
        peekEndWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func endPeek() {
        peekEndWork = nil
        guard model.state == .peek else { return }
        model.peek = nil
        panel?.ignoresMouseEvents = true
        if inboxWanted {
            model.state = .inbox
        } else if playerWanted {
            model.state = .compact
        } else {
            hide()
        }
    }

    // MARK: - Show / hide

    private func show() {
        hideWork?.cancel()
        hideWork = nil
        if panel == nil { makePanel() }
        guard let panel = panel else { return }
        if !panel.isVisible {
            relayout()
            model.state = .hidden
            panel.orderFrontRegardless()
            startPointerTracking()
        }
        // Grow out of the notch on the next frame, so the change animates.
        if model.state == .hidden {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.hideWork == nil, self.model.state == .hidden else { return }
                if self.inboxWanted { self.settleState() } else { self.model.state = .compact }
            }
        }
    }

    private func hide() {
        guard let panel = panel, panel.isVisible, hideWork == nil else { return }
        model.state = .hidden
        panel.ignoresMouseEvents = true
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.hideWork = nil
            guard self.model.state == .hidden else { return }
            self.panel?.orderOut(nil)
            self.stopPointerTracking()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    // MARK: - Window

    private func makePanel() {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Over the menu bar, like the notch itself.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentViewController = NSHostingController(rootView: NotchView(
            model: model, nowPlaying: nowPlaying, messages: messages,
            actions: NotchActions(
                playPause: { [weak self] in self?.nowPlaying.playPause() },
                next: { [weak self] in self?.nowPlaying.next() },
                previous: { [weak self] in self?.nowPlaying.previous() },
                openPlayer: { [weak self] in self?.nowPlaying.openPlayer() },
                openMessage: { [weak self] message in
                    self?.openApp(message.app)
                    self?.endPeek()
                },
                openApp: { [weak self] app in self?.openApp(app) })))
        self.panel = panel
        relayout()
    }

    /// Measures the notch and places the window centred under it.
    private func relayout() {
        guard let panel = panel else { return }
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = screen else { return }
        self.screen = screen

        let frame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            model.hasNotch = true
            model.notch = CGSize(width: frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        } else {
            model.hasNotch = false
            model.notch = CGSize(width: 12, height: max(24, frame.maxY - screen.visibleFrame.maxY))
        }
        let canvas = model.canvas
        let centerX = screen.safeAreaInsets.top > 0 && screen.auxiliaryTopLeftArea != nil
            ? frame.minX + (screen.auxiliaryTopLeftArea?.width ?? 0) + model.notch.width / 2
            : frame.midX
        panel.setFrame(CGRect(x: (centerX - canvas.width / 2).rounded(), y: frame.maxY - canvas.height,
                              width: canvas.width, height: canvas.height), display: true)
    }

    // MARK: - Pointer

    /// Polls the pointer while the player is up (cheap; no event monitors or
    /// permissions): hovering expands it, leaving collapses it.
    private func startPointerTracking() {
        guard pointerTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.trackPointer() }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private func stopPointerTracking() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        collapseWork?.cancel()
        collapseWork = nil
    }

    private func trackPointer() {
        guard let panel = panel, model.state != .hidden else { return }
        let point = NSEvent.mouseLocation
        let inside = visibleRect(for: model.state, in: panel.frame).insetBy(dx: -6, dy: -6).contains(point)

        switch (model.state, inside) {
        case (.compact, true):
            collapseWork?.cancel()
            if let key = NSApp.keyWindow, key !== panel { keyWindowBeforeExpanding = key }
            model.state = .expanded
            panel.ignoresMouseEvents = false
        case (.expanded, false):
            guard collapseWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.collapseWork = nil
                guard self.model.state == .expanded else { return }
                self.model.state = .compact
                self.panel?.ignoresMouseEvents = true
                // Clicking a button made the player key; give focus back
                // (e.g. so the grid editor's arrow keys keep working).
                if self.panel?.isKeyWindow == true, let previous = self.keyWindowBeforeExpanding,
                   previous.isVisible {
                    previous.makeKey()
                }
                self.keyWindowBeforeExpanding = nil
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        case (.expanded, true):
            collapseWork?.cancel()
            collapseWork = nil
        case (.peek, true):
            // Reading it: keep it up while the pointer is there.
            peekEndWork?.cancel()
            peekEndWork = nil
        case (.peek, false):
            if peekEndWork == nil { schedulePeekEnd(after: 1.5) }
        case (.inbox, true):
            // Take clicks only while the pointer is on the inbox itself.
            if panel.ignoresMouseEvents { panel.ignoresMouseEvents = false }
        case (.inbox, false):
            if !panel.ignoresMouseEvents { panel.ignoresMouseEvents = true }
            if model.hoveredApp != nil { model.hover(nil, messageCount: 0) }
        default:
            break
        }
    }

    /// Where the black shape is on screen, for a state.
    private func visibleRect(for state: NotchModel.State, in window: CGRect) -> CGRect {
        let size = model.size(for: state)
        return CGRect(x: window.midX - size.width / 2, y: window.maxY - size.height,
                      width: size.width, height: size.height)
    }
}
