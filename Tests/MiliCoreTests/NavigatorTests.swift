import XCTest
@testable import MiliCore

/// Grid used throughout: row 1 = 1…3, row 2 = 4…8 (the example from the spec).
final class NavigatorTests: XCTestCase {

    private let rows = [["1", "2", "3"], ["4", "5", "6", "7", "8"]]
    private let rules = NavigationRules()   // wrap both ways, first-of-row

    private func go(_ from: String?, _ dir: NavDirection,
                    _ rules: NavigationRules? = nil) -> String? {
        Navigator.target(from: from, direction: dir, rows: rows, rules: rules ?? self.rules)
    }

    // MARK: Spec examples

    func testDownFromTwoLandsOnFirstOfNextRow() { XCTAssertEqual(go("2", .down), "4") }
    func testLeftFromFirstWrapsToEndOfRow()     { XCTAssertEqual(go("4", .left), "8") }
    func testRightFromLastWrapsToStartOfRow()   { XCTAssertEqual(go("8", .right), "4") }
    func testUpFromSecondRowLandsOnFirstOfRow() { XCTAssertEqual(go("4", .up), "1") }

    // MARK: Horizontal stays inside the row

    func testHorizontalNeverLeavesRow() {
        XCTAssertEqual(go("3", .right), "1")
        XCTAssertEqual(go("1", .left), "3")
        XCTAssertEqual(go("5", .right), "6")
        XCTAssertEqual(go("6", .left), "5")
    }

    func testNoHorizontalWrap() {
        var r = rules; r.wrapHorizontally = false
        XCTAssertNil(go("3", .right, r))
        XCTAssertNil(go("4", .left, r))
        XCTAssertEqual(go("4", .right, r), "5")
    }

    // MARK: Vertical

    func testVerticalWrap() {
        XCTAssertEqual(go("5", .down), "1")   // bottom row → wraps to top
        XCTAssertEqual(go("2", .up), "4")     // top row → wraps to bottom
    }

    func testNoVerticalWrap() {
        var r = rules; r.wrapVertically = false
        XCTAssertNil(go("5", .down, r))
        XCTAssertNil(go("2", .up, r))
    }

    func testSameColumnLandingClamps() {
        var r = rules; r.verticalLanding = .sameColumn
        XCTAssertEqual(go("2", .down, r), "5")   // column 1 → column 1
        XCTAssertEqual(go("8", .up, r), "3")     // column 4 clamps to row 1's last
        XCTAssertEqual(go("6", .up, r), "3")
    }

    // MARK: Edge cases

    func testUnknownCurrentGoesToFirstDesktop() {
        XCTAssertEqual(go(nil, .right), "1")
        XCTAssertEqual(go("fullscreen-app", .down), "1")
    }

    func testSingleItemRowGoesNowhereHorizontally() {
        let single = [["A"], ["B", "C"]]
        XCTAssertNil(Navigator.target(from: "A", direction: .right, rows: single, rules: rules))
    }

    func testEmptyRowsAreSkipped() {
        let withGap = [["1", "2"], [], ["3"]]
        XCTAssertEqual(Navigator.target(from: "1", direction: .down, rows: withGap, rules: rules), "3")
    }

    func testEmptyGrid() {
        XCTAssertNil(Navigator.target(from: "1", direction: .left, rows: [[]], rules: rules))
    }
}
