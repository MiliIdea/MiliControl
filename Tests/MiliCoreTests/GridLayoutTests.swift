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

    // MARK: - Native order

    func testSortedWithinRowsKeepsMembershipAndNames() {
        let numbers = ["a": 1, "b": 2, "c": 3, "d": 4, "e": 5]
        let l = GridLayout(rows: [["c", "a"], ["e", "b", "d"]], rowNames: ["Home", "Work"])
        let s = l.sortedWithinRows { numbers[$0] }
        XCTAssertEqual(s.rows, [["a", "c"], ["b", "d", "e"]])
        XCTAssertEqual(s.rowNames, ["Home", "Work"])
    }

    func testSortedWithinRowsPutsUnknownKeysLastInOrder() {
        let numbers = ["a": 2, "b": 1]
        let l = GridLayout(rows: [["x", "a", "y", "b"], []])
        XCTAssertEqual(l.sortedWithinRows { numbers[$0] }.rows, [["b", "a", "x", "y"], []])
    }

    func testSortedWithinRowsIsIdempotent() {
        let numbers = ["a": 1, "b": 2]
        let l = GridLayout(rows: [["b", "a"]]).sortedWithinRows { numbers[$0] }
        XCTAssertEqual(l, l.sortedWithinRows { numbers[$0] })
    }

    // MARK: - Fullscreen apps

    func testReconcileRetainsDormantKeys() {
        let l = GridLayout(rows: [["a", "fs:x"], ["b"]])
        let r = l.reconciled(with: ["a", "b"], retaining: { $0.hasPrefix("fs:") })
        XCTAssertEqual(r.rows, [["a", "fs:x"], ["b"]])
    }

    func testReconcilePlacesNewKeyBesideItsNeighbor() {
        let l = GridLayout(rows: [["a", "b"], ["c"]])
        let r = l.reconciled(with: ["a", "fs:x", "b", "c", "d"], besideNeighbor: { $0.hasPrefix("fs:") })
        XCTAssertEqual(r.rows, [["a", "fs:x", "b"], ["c", "d"]])
    }

    func testReconcileNewKeyWithoutNeighborGoesLast() {
        let l = GridLayout(rows: [["a"]])
        let r = l.reconciled(with: ["fs:x", "a"], besideNeighbor: { $0.hasPrefix("fs:") })
        XCTAssertEqual(r.rows, [["a", "fs:x"]])
    }
}
