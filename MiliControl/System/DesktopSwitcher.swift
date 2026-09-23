//
//  DesktopSwitcher.swift
//  MiliControl
//
//  Switches desktops the native way: by sending macOS's own shortcuts.
//
//    • Desktop with a "Switch to Desktop N" shortcut → one keystroke, one
//      native slide straight there.
//    • Desktop without one (Desktops 10–16 before you assign keys) → the
//      shortest route RoutePlanner finds: optionally a jump to the nearest
//      shortcut desktop, then "Move left/right a space" steps. Each step is
//      sent only after the previous slide has finished, so macOS never drops
//      or merges them.
//
//  Sending keystrokes requires Accessibility access. Without it macOS
//  silently drops them, so we check first and report instead.
//

import AppKit
import ApplicationServices

enum SwitchOutcome: Equatable {
    /// On its way. `slides` = how many native slides it takes (1 = direct).
    case sent(slides: Int)
    case notTrusted
    /// No shortcut to jump to it and "Move left/right a space" is off (or the
    /// desktop is beyond what macOS can switch to).
    case unreachable(desktop: Int)
}

final class DesktopSwitcher {

    /// Modifier flag → the physical key that produces it.
    private static let modifierKeys: [(flag: CGEventFlags, keyCode: CGKeyCode)] = [
        (.maskControl, 0x3B),
        (.maskAlternate, 0x3A),
        (.maskShift, 0x38),
        (.maskCommand, 0x37),
    ]
    /// Longest we wait for a slide to finish before sending the next step.
    private static let stepTimeout: TimeInterval = 1.2

    private var queuedSteps: [KeyCombo] = []
    private var stepObserver: NSObjectProtocol?
    private var stepTimeoutWork: DispatchWorkItem?
    /// Bumped whenever a route is replaced, so a step scheduled for the old
    /// route can never fire into the new one.
    private var sequenceID = 0
    /// The space we were on when the current step was sent; only a change
    /// away from it means that step's slide has landed.
    private var spaceBeforeStep: CGSSpaceID = 0
    private let connection = CGSMainConnectionID()

    var isTrusted: Bool { AXIsProcessTrusted() }

    deinit { cancelSequence() }

    func switchTo(_ target: Desktop, in store: DesktopStore,
                  shortcuts: [Int: SymbolicHotKey]) -> SwitchOutcome {
        guard isTrusted else { return .notTrusted }
        cancelSequence()                        // a new switch replaces any route in progress

        // "Move left/right a space" only moves within one display, so plan
        // on the target's display only.
        let strip = store.strips[target.displayID] ?? []
        let position: [CGSSpaceID: Int] = Dictionary(strip.enumerated().map { ($0.element, $0.offset) },
                                                     uniquingKeysWith: { first, _ in first })
        guard SymbolicHotKeys.switchableDesktops.contains(target.number),
              let to = position[target.spaceID] else { return .unreachable(desktop: target.number) }

        var jumpTargets: [Int: Int] = [:]
        for desktop in store.desktops where desktop.displayID == target.displayID {
            if SymbolicHotKeys.usableSwitchCombo(forDesktop: desktop.number, in: shortcuts) != nil,
               let index = position[desktop.spaceID] {
                jumpTargets[desktop.number] = index
            }
        }
        let left = SymbolicHotKeys.moveSpaceCombo(left: true, in: shortcuts)
        let right = SymbolicHotKeys.moveSpaceCombo(left: false, in: shortcuts)

        guard let route = RoutePlanner.route(from: position[store.activeSpaceID], to: to,
                                             targetNumber: target.number,
                                             jumpTargets: jumpTargets,
                                             canStep: left != nil && right != nil)
        else { return .unreachable(desktop: target.number) }

        let combos = route.compactMap { step -> KeyCombo? in
            switch step {
            case .jump(let number): return SymbolicHotKeys.usableSwitchCombo(forDesktop: number, in: shortcuts)
            case .left: return left
            case .right: return right
            }
        }
        guard combos.count == route.count else { return .unreachable(desktop: target.number) }
        run(combos)
        return .sent(slides: combos.count)
    }

    // MARK: - Multi-step routes

    private func run(_ combos: [KeyCombo]) {
        guard let first = combos.first else { return }
        queuedSteps = Array(combos.dropFirst())
        if !queuedSteps.isEmpty { waitForSlideThenContinue() }   // records the space before the first slide
        post(first)
    }

    private func waitForSlideThenContinue() {
        clearWaiters()
        spaceBeforeStep = CGSGetActiveSpace(connection)
        stepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                // Ignore late notifications from an earlier slide.
                guard let self = self,
                      CGSGetActiveSpace(self.connection) != self.spaceBeforeStep else { return }
                self.advance()
            }
        let timeout = DispatchWorkItem { [weak self] in self?.advance() }
        stepTimeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stepTimeout, execute: timeout)
    }

    private func advance() {
        clearWaiters()
        guard !queuedSteps.isEmpty else { return }
        let next = queuedSteps.removeFirst()
        let id = sequenceID
        // A beat after the slide lands, so macOS is ready for the next one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self, self.sequenceID == id else { return }   // route was replaced
            self.post(next)
            if !self.queuedSteps.isEmpty { self.waitForSlideThenContinue() }
        }
    }

    private func cancelSequence() {
        sequenceID += 1
        queuedSteps.removeAll()
        clearWaiters()
    }

    private func clearWaiters() {
        if let observer = stepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            stepObserver = nil
        }
        stepTimeoutWork?.cancel()
        stepTimeoutWork = nil
    }

    // MARK: - Posting keystrokes

    /// Posts the combo as a real key chord, correct even while the user is
    /// still physically holding other modifiers (e.g. ⌃⌥ from MiliControl's
    /// own shortcut — macOS would otherwise see ⌃⌥N and ignore it):
    ///
    ///   1. lift modifiers that are held but not part of the combo (⌥),
    ///   2. press modifiers the combo needs that aren't held,
    ///   3. key down / key up,
    ///   4. undo steps 2 and 1, so macOS's modifier state again matches the
    ///      keys that are physically down — nothing is left "stuck".
    private func post(_ combo: KeyCombo) {
        let source = CGEventSource(stateID: .hidSystemState)
        let held = CGEventSource.flagsState(.combinedSessionState)
        let extra = Self.modifierKeys.filter { held.contains($0.flag) && !combo.flags.contains($0.flag) }
        let missing = Self.modifierKeys.filter { combo.flags.contains($0.flag) && !held.contains($0.flag) }

        var flags = held.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
        for modifier in extra {
            flags.remove(modifier.flag)
            send(source, modifier.keyCode, down: false, flags: flags)
        }
        for modifier in missing {
            flags.insert(modifier.flag)
            send(source, modifier.keyCode, down: true, flags: flags)
        }

        send(source, combo.keyCode, down: true, flags: combo.flags)
        send(source, combo.keyCode, down: false, flags: combo.flags)

        for modifier in missing.reversed() {
            flags.remove(modifier.flag)
            send(source, modifier.keyCode, down: false, flags: flags)
        }
        for modifier in extra.reversed() {
            flags.insert(modifier.flag)
            send(source, modifier.keyCode, down: true, flags: flags)
        }
    }

    private func send(_ source: CGEventSource?, _ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
        else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}
