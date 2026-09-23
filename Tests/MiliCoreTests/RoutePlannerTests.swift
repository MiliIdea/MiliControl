import XCTest
@testable import MiliCore

/// Strip used below: positions 0…11 are Desktops 1…12 in order.
/// Desktops 1–9 have shortcuts; 10–12 don't.
final class RoutePlannerTests: XCTestCase {

    private let jumps = Dictionary(uniqueKeysWithValues: (1...9).map { ($0, $0 - 1) })

    func testDirectJumpWhenShortcutExists() {
        XCTAssertEqual(RoutePlanner.route(from: 0, to: 4, targetNumber: 5,
                                          jumpTargets: jumps, canStep: true),
                       [.jump(desktop: 5)])
    }

    func testAlreadyThere() {
        XCTAssertEqual(RoutePlanner.route(from: 3, to: 3, targetNumber: 4,
                                          jumpTargets: jumps, canStep: true), [])
    }

    func testDesktop10FromFarAwayJumpsTo9ThenSteps() {
        // From Desktop 1: stepping would take 9 slides; jump to 9 + 1 step = 2.
        XCTAssertEqual(RoutePlanner.route(from: 0, to: 9, targetNumber: 10,
                                          jumpTargets: jumps, canStep: true),
                       [.jump(desktop: 9), .right])
    }

    func testNeighbourStepsWithoutJumping() {
        // From Desktop 11 to 12: one step beats jump+3.
        XCTAssertEqual(RoutePlanner.route(from: 10, to: 11, targetNumber: 12,
                                          jumpTargets: jumps, canStep: true),
                       [.right])
    }

    func testStepsLeftWhenNeeded() {
        XCTAssertEqual(RoutePlanner.route(from: 11, to: 9, targetNumber: 10,
                                          jumpTargets: jumps, canStep: true),
                       [.left, .left])
    }

    func testUnknownCurrentPositionUsesAJump() {
        XCTAssertEqual(RoutePlanner.route(from: nil, to: 10, targetNumber: 11,
                                          jumpTargets: jumps, canStep: true),
                       [.jump(desktop: 9), .right, .right])
    }

    func testUnreachableWithoutShortcutOrStepping() {
        XCTAssertNil(RoutePlanner.route(from: 0, to: 9, targetNumber: 10,
                                        jumpTargets: jumps, canStep: false))
    }

    func testFullscreenSpacesCountAsSteps() {
        // Desktop 9 at position 8, a fullscreen app at 9, Desktop 10 at 10.
        XCTAssertEqual(RoutePlanner.route(from: 0, to: 10, targetNumber: 10,
                                          jumpTargets: jumps, canStep: true),
                       [.jump(desktop: 9), .right, .right])
    }
}
