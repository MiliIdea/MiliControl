//
//  RoutePlanner.swift
//  MiliControl
//
//  Decides how to reach a desktop with the fewest slides:
//
//    • if it has a "Switch to Desktop N" shortcut → one direct jump;
//    • otherwise (e.g. Desktops 10–16 before you assign keys) → step with
//      "Move left/right a space", either from where you are or after jumping
//      to whichever shortcut-enabled desktop is closest — whichever is shorter.
//
//  Positions are indexes in macOS's full space strip (fullscreen apps
//  included), because that's what the move-a-space shortcut walks.
//
//  Pure Foundation — unit-tested in Tests/MiliCoreTests.
//

import Foundation

enum RouteStep: Equatable {
    /// Send "Switch to Desktop N".
    case jump(desktop: Int)
    case left
    case right
}

enum RoutePlanner {

    /// - Parameters:
    ///   - from: your current strip position (nil if unknown).
    ///   - to: the target's strip position.
    ///   - targetNumber: the target's desktop number.
    ///   - jumpTargets: desktop number → strip position, for every desktop
    ///     that has a usable "Switch to Desktop N" shortcut.
    ///   - canStep: whether "Move left/right a space" are available.
    /// - Returns: the steps to perform ([] when already there), or nil if
    ///   the desktop can't be reached.
    static func route(from: Int?, to: Int, targetNumber: Int,
                      jumpTargets: [Int: Int], canStep: Bool) -> [RouteStep]? {
        if from == to { return [] }
        if jumpTargets[targetNumber] != nil { return [.jump(desktop: targetNumber)] }
        guard canStep else { return nil }

        var best: [RouteStep]?
        if let from = from { best = steps(from: from, to: to) }
        for number in jumpTargets.keys.sorted() {
            guard let position = jumpTargets[number] else { continue }
            let candidate = [RouteStep.jump(desktop: number)] + steps(from: position, to: to)
            if best == nil || candidate.count < best!.count { best = candidate }
        }
        return best
    }

    private static func steps(from: Int, to: Int) -> [RouteStep] {
        Array(repeating: to > from ? .right : .left, count: abs(to - from))
    }
}
