import XCTest
@testable import MiliCore

final class GridLayoutTests: XCTestCase {

    func testChunked() {
        let l = GridLayout.chunked(["a", "b", "c", "d", "e"], perRow: 2)
        XCTAssertEqual(l.rows, [["a", "b"], ["c", "d"], ["e"]])
        XCTAssertEqual(GridLayout.chunked([]).rows, [[]])
    }

    func testReconcileKeepsUserOrderDropsGoneAppendsNew() {
        let l = GridLayout(rows: [["c", "a"], ["gone", "b"]])
        let r = l.reconciled(with: ["a", "b", "c", "new1", "new2"])
        XCTAssertEqual(r.rows, [["c", "a"], ["b", "new1", "new2"]])
    }

    func testReconcileKeepsEmptyRowsAndDeduplicates() {
        let l = GridLayout(rows: [["a", "a"], []])
        let r = l.reconciled(with: ["a", "b"])
        XCTAssertEqual(r.rows, [["a"], ["b"]])
    }

    func testReconcileEmptyLayout() {
        XCTAssertEqual(GridLayout().reconciled(with: ["x"]).rows, [["x"]])
    }

    func testMoveWithinRowUsesFinalIndex() {
        var l = GridLayout(rows: [["a", "b", "c"]])
        l.move("a", toRow: 0, index: 2)
        XCTAssertEqual(l.rows, [["b", "c", "a"]])
        l.move("a", toRow: 0, index: 0)
        XCTAssertEqual(l.rows, [["a", "b", "c"]])
    }

    func testMoveAcrossRowsAndAppend() {
        var l = GridLayout(rows: [["a", "b"], ["c"]])
        l.move("a", toRow: 1, index: 0)
        XCTAssertEqual(l.rows, [["b"], ["a", "c"]])
        l.move("b", toRow: 1, index: .max)
        XCTAssertEqual(l.rows, [[], ["a", "c", "b"]])
        l.move("c", toRow: 2, index: 0)          // creates the row
        XCTAssertEqual(l.rows, [[], ["a", "b"], ["c"]])
    }

    func testRemoveRowNeverLosesDesktops() {
        var l = GridLayout(rows: [["a"], ["b", "c"], ["d"]])
        l.removeRow(at: 1)
        XCTAssertEqual(l.rows, [["a", "b", "c"], ["d"]])
        l.removeRow(at: 0)
        XCTAssertEqual(l.rows, [["d", "a", "b", "c"]])
        l.removeRow(at: 0)                       // last row can't be removed
        XCTAssertEqual(l.rows, [["d", "a", "b", "c"]])
    }

    func testCodableRoundTrip() throws {
        var l = GridLayout(rows: [["a", "b"], ["c"]])
        l.renameRow(1, to: "Design")
        let data = try JSONEncoder().encode(l)
        XCTAssertEqual(try JSONDecoder().decode(GridLayout.self, from: data), l)
    }

    // MARK: Row names

    func testDecodesLayoutSavedBeforeRowNames() throws {
        let old = #"{"rows":[["a"],["b","c"]]}"#.data(using: .utf8)!
        let l = try JSONDecoder().decode(GridLayout.self, from: old)
        XCTAssertEqual(l.rows, [["a"], ["b", "c"]])
        XCTAssertEqual(l.rowNames, ["", ""])
        XCTAssertEqual(l.displayName(ofRow: 1), "Row 2")
    }

    func testNamesAndDefaults() {
        var l = GridLayout(rows: [["a"], ["b"]])
        l.renameRow(0, to: "  Work  ")
        XCTAssertEqual(l.displayName(ofRow: 0), "Work")     // trimmed
        XCTAssertEqual(l.rawName(ofRow: 0), "  Work  ")     // raw kept for editing
        l.renameRow(1, to: "   ")
        XCTAssertNil(l.name(ofRow: 1))
        XCTAssertEqual(l.displayName(ofRow: 1), "Row 2")
    }

    func testNamesFollowTheirRows() {
        var l = GridLayout(rows: [["a"], ["b"], ["c"]], rowNames: ["Work", "Design", "Chat"])
        l.removeRow(at: 1)                                  // "Design" goes, its desktop moves up
        XCTAssertEqual(l.rows, [["a", "b"], ["c"]])
        XCTAssertEqual(l.rowNames, ["Work", "Chat"])
        l.addRow()
        XCTAssertEqual(l.rowNames, ["Work", "Chat", ""])
        l.move("a", toRow: 4, index: 0)                     // creates rows 3 and 4
        XCTAssertEqual(l.rowNames.count, l.rows.count)
        let r = l.reconciled(with: ["a", "b", "c", "new"])
        XCTAssertEqual(Array(r.rowNames.prefix(2)), ["Work", "Chat"])
    }
}
