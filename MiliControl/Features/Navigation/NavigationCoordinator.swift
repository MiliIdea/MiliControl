//
//  NavigationCoordinator.swift
//  MiliControl
//
//  Turns ⌃⌥ + arrow presses into desktop switches. What happens depends on
//  how long the ARROW key is held (how long ⌃⌥ are held doesn't matter):
//
//    • Tap (arrow released within 0.3 s): switch immediately to the
//      neighbouring desktop — no overlay. Keep holding ⌃⌥ and tap again to
//      keep moving, one slide per tap.
//
//    • Hold (arrow still down after 0.3 s): grid mode. The HUD appears with
//      the destination highlighted; further arrow taps move the highlight
//      without switching. Releasing ⌃⌥ switches once, straight there.
//
//  Switching always goes through macOS's own "Switch to Desktop N" shortcut
//  (DesktopSwitcher), so every move is the native slide. About a second after
//  each switch we confirm you arrived, and say exactly what to fix if not.
//

import AppKit
import Combine
import os

final class NavigationCoordinator {

    private let desktops: DesktopStore
    private let layout: LayoutStore
    private let prefs: Preferences
    private let switcher: DesktopSwitcher
    private let hud: HUDController
    private let snapshots: DesktopSnapshots
    private var snapshotSubscription: AnyCancellable?
    private let log = Logger(subsystem: "com.mili.MiliControl", category: "navigation")

    /// If the grid editor is open, it gets arrow presses instead (returns true
    /// when it handled them).
    var editorRouter: ((NavDirection) -> Bool)?
    /// Called when a switch failed because of a setup problem.
    var onSetupProblem: (() -> Void)?

    // MARK: State

    /// Where the current press / grid selection will take you.
    private var pendingKey: String?
    /// The arrow that is physically down right now (ignores auto-repeat and
    /// chords of several arrows).
    private var heldArrow: NavDirection?
    /// Fires after `longPressDelay` if the arrow is still down → grid mode.
    private var longPressWork: DispatchWorkItem?
    /// Grid mode: HUD on screen, arrows move the selection, releasing ⌃⌥ commits.
    private var inGridMode = false
    private var hudVisible = false

    /// The desktop we just switched to. macOS reports the old desktop until
    /// the slide finishes, so quick successive taps must continue from here.
    /// `until` = when the slide(s) should be over.
    private var lastCommit: (key: String, until: Date)?
    /// Desktops we've already shown the "assign a shortcut" tip for.
    private var tippedDesktops = Set<Int>()

    private var releaseTimer: Timer?
    private var releaseDeadline = Date.distantPast
    private var verifyWork: DispatchWorkItem?

    private static let longPressDelay: TimeInterval = 0.3
    /// Roughly how long one native slide takes.
    private static let slideDuration: TimeInterval = 0.8
    /// Safety net for grid mode, in case a modifier is reported held forever.
    private static let releaseTimeout: TimeInterval = 10
    private static let modifierMask: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]

    init(desktops: DesktopStore, layout: LayoutStore, prefs: Preferences,
         switcher: DesktopSwitcher, hud: HUDController, snapshots: DesktopSnapshots) {
        self.desktops = desktops
        self.layout = layout
        self.prefs = prefs
        self.switcher = switcher
        self.hud = hud
        self.snapshots = snapshots
        // A fresh snapshot (e.g. the one taken as the grid opens) updates the
        // grid that's already on screen.
        snapshotSubscription = snapshots.$images
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, self.hudVisible, self.inGridMode else { return }
                self.updateHUD()
            }
    }

    // MARK: - Hotkey entry points

    func arrowPressed(_ direction: NavDirection) {
        if editorRouter?(direction) == true { return }

        if inGridMode {
            guard heldArrow != direction else { return }       // auto-repeat
            heldArrow = direction
            if step(direction) { updateHUD() }
            releaseDeadline = Date().addingTimeInterval(Self.releaseTimeout)
            return
        }

        guard heldArrow == nil else { return }                 // auto-repeat / chord
        desktops.refresh()                                     // trackpad may have moved you
        guard step(direction) else { return }
        heldArrow = direction
        if prefs.showHUD { scheduleGridMode() }
    }

    func arrowReleased(_ direction: NavDirection) {
        guard heldArrow == direction else { return }
        heldArrow = nil
        guard !inGridMode else { return }                      // grid mode waits for ⌃⌥ release
        longPressWork?.cancel()
        longPressWork = nil
        commit()                                               // quick tap → go now
    }

    /// A four-finger swipe: one step in the grid, switched immediately (no
    /// grid HUD — like a quick arrow tap). In the grid editor it moves the
    /// selection instead.
    func swipe(_ direction: NavDirection) {
        if editorRouter?(direction) == true { return }
        guard !inGridMode, heldArrow == nil else { return }   // keyboard navigation in progress
        desktops.refresh()
        guard step(direction) else { return }
        commit()
    }

    /// Immediate switch (e.g. clicking a tile in the grid editor).
    func switchNow(to key: String) {
        longPressWork?.cancel()
        longPressWork = nil
        stopReleaseWatch()
        inGridMode = false
        heldArrow = nil
        pendingKey = key
        commit()
    }

    // MARK: - Navigation

    /// Moves `pendingKey` one step. Returns false if there's nowhere to go.
    @discardableResult
    private func step(_ direction: NavDirection) -> Bool {
        let rows = layout.navigableRows()
        let recent = lastCommit.flatMap { commit -> String? in
            Date() < commit.until && desktops.currentKey != commit.key ? commit.key : nil
        }
        let base = pendingKey ?? recent ?? desktops.currentKey
        guard let target = Navigator.target(from: base, direction: direction,
                                            rows: rows, rules: prefs.rules) else {
            if rows.allSatisfy(\.isEmpty) { hud.flash("There are no desktops in your grid yet.") }
            return false
        }
        pendingKey = target
        return true
    }

    // MARK: - Grid mode (long press)

    private func scheduleGridMode() {
        longPressWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.longPressWork = nil
            guard self.pendingKey != nil, self.heldArrow != nil else { return }
            self.enterGridMode()
        }
        longPressWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.longPressDelay, execute: work)
    }

    private func enterGridMode() {
        inGridMode = true
        snapshots.captureNow()          // refresh the desktop you're on before it's shown
        desktops.refreshApps()          // icons, only when shown
        hudVisible = true
        updateHUD()
        waitForModifierRelease()
    }

    private func waitForModifierRelease() {
        releaseDeadline = Date().addingTimeInterval(Self.releaseTimeout)
        guard releaseTimer == nil else { return }
        let timer = Timer(timeInterval: 0.012, repeats: true) { [weak self] _ in
            self?.checkModifiers()
        }
        RunLoop.main.add(timer, forMode: .common)
        releaseTimer = timer
    }

    private func checkModifiers() {
        let held = CGEventSource.flagsState(.combinedSessionState).intersection(Self.modifierMask)
        if held.isEmpty || Date() >= releaseDeadline {
            stopReleaseWatch()
            inGridMode = false
            heldArrow = nil
            commit()
        }
    }

    private func stopReleaseWatch() {
        releaseTimer?.invalidate()
        releaseTimer = nil
    }

    // MARK: - Switching

    private func commit() {
        verifyWork?.cancel()
        guard let key = pendingKey else { dismissHUD(after: 0.1); return }
        pendingKey = nil

        desktops.refresh()
        guard let desktop = desktops.desktop(forKey: key) else {
            dismissHUD(after: 0.1)
            return
        }
        if desktop.key == desktops.currentKey {
            dismissHUD(after: 0.15)
            return
        }

        // Remove the grid on the desktop you're leaving, before the slide
        // starts — not after, on the destination.
        if hudVisible {
            hudVisible = false
            hud.hideImmediately()
        }
        let outcome = switcher.switchTo(desktop, in: desktops, shortcuts: SymbolicHotKeys.read())

        switch outcome {
        case .sent(let slides):
            // First slide, plus for each extra step: its slide, the wait for it
            // to land, and headroom in case a step falls back to its timeout.
            let duration: TimeInterval = Self.slideDuration + Double(max(slides - 1, 0)) * 1.3
            snapshots.switchWillStart(duration: duration + 0.7)   // no previews mid-slide
            lastCommit = (key, Date().addingTimeInterval(duration))
            log.debug("Switching to desktop \(desktop.number, privacy: .public) in \(slides, privacy: .public) slide(s)")
            verifyArrival(at: key, number: desktop.number, after: duration + 0.6)
            if slides > 1 { tipAboutShortcut(for: desktop.number, after: duration) }
        case .notTrusted:
            hud.flash("MiliControl needs Accessibility access to switch desktops. Open MiliControl Settings to fix it.")
            onSetupProblem?()
        case .unreachable(let number):
            if SymbolicHotKeys.switchableDesktops.contains(number) {
                hud.flash("Can't reach Desktop \(number): give it a “Switch to Desktop \(number)” shortcut, or turn on “Move left/right a space”, in Keyboard Shortcuts ▸ Mission Control.",
                          duration: 5)
                onSetupProblem?()
            } else {
                hud.flash("Desktop \(number) can't be reached — macOS supports switching to Desktops 1–16.")
            }
        }
    }

    /// Once per desktop per session: explain how to make a multi-slide switch
    /// instant. Shown after arriving, so it doesn't interrupt the slides.
    private func tipAboutShortcut(for number: Int, after delay: TimeInterval) {
        guard !tippedDesktops.contains(number) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            // If you're already navigating again, save the tip for next time.
            guard let self = self, self.pendingKey == nil,
                  !self.tippedDesktops.contains(number) else { return }
            self.tippedDesktops.insert(number)
            let fix: String = SymbolicHotKeys.defaultShortcutDesktops.contains(number)
                ? "turn on “Switch to Desktop \(number)” in Keyboard Shortcuts ▸ Mission Control."
                : "assign “Switch to Desktop \(number)” a shortcut — see MiliControl Settings ▸ Desktops 10–16."
            self.hud.flash("Desktop \(number) has no active shortcut, so it took a few slides. For one instant slide, \(fix)",
                           duration: 5)
        }
    }

    /// Confirms the switch happened; if not, the shortcut is most likely off
    /// or remapped in a way we couldn't read.
    private func verifyArrival(at key: String, number: Int, after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.pendingKey == nil else { return }
            self.desktops.refresh()
            guard self.desktops.currentKey != key else { return }
            // A newer switch may have superseded this one.
            if let last = self.lastCommit, last.key != key { return }
            self.log.error("Switch to desktop \(number, privacy: .public) did not happen")
            self.hud.flash("Couldn't switch to Desktop \(number). Check “Switch to Desktop \(number)” in Keyboard Shortcuts, or open MiliControl Settings.")
            self.onSetupProblem?()
        }
        verifyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - HUD

    private func dismissHUD(after delay: TimeInterval) {
        guard hudVisible else { return }
        hudVisible = false
        hud.hide(after: delay)
    }

    private func updateHUD() {
        guard let target = pendingKey else { return }
        let rows = layout.navigableRows()
        let byKey = Dictionary(desktops.desktops.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let grid = layout.layout
        let previews = snapshots.isActive
        let images = previews ? snapshots.images : [:]
        let hudRows = rows.enumerated().compactMap { pair -> HUDRow? in
            let (index, row) = pair
            let cells = row.compactMap { key -> HUDCell? in
                guard let desktop = byKey[key] else { return nil }
                return HUDCell(key: key,
                               number: desktop.number,
                               pid: desktops.apps[key]?.first?.pid,
                               title: DesktopLabel.title(for: key, number: desktop.number, in: desktops),
                               snapshot: images[key])
            }
            return cells.isEmpty ? nil : HUDRow(id: index, name: grid.displayName(ofRow: index), cells: cells)
        }
        hud.model.usesPreviews = previews
        hud.model.cellSize = HUDMetrics.cellSize(previews: previews,
                                                 columns: hudRows.map(\.cells.count).max() ?? 1,
                                                 screen: NSScreen.main)
        hud.model.rows = hudRows
        hud.model.targetKey = target
        hud.model.currentKey = desktops.currentKey
        hud.show()
    }
}
