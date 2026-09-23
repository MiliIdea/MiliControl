//
//  Navigator.swift
//  MiliControl
//
//  The movement rules for the grid. Given where you are and a direction, it
//  decides which desktop to go to:
//
//    • Left / right move within the current row only. At a row's edge they
//      wrap to the other end of the same row (configurable).
//    • Up / down move to the previous / next row. Which column you land on is
//      configurable: the first desktop of that row, or the same column
//      (clamped to the row's length). Moving past the top/bottom row can wrap.
//
//  Pure Foundation — unit-tested in Tests/MiliCoreTests.
//

import Foundation

enum NavDirection: String, CaseIterable {
    case left, right, up, down
}

/// Where up/down lands in the destination row.
enum VerticalLanding: String, CaseIterable, Codable, Identifiable {
    /// Always the first desktop of the row (e.g. 2 ↓ → 4 when row 2 is 4…8).
    case firstOfRow
    /// The same column, clamped to the destination row's length.
    case sameColumn

    var id: String { rawValue }
}

struct NavigationRules: Equatable, Codable {
    var wrapHorizontally = true
    var wrapVertically = true
    var verticalLanding: VerticalLanding = .firstOfRow
}

enum Navigator {

    /// Returns the key to switch to, or `nil` when the move goes nowhere
    /// (edge without wrap, single-element row, etc.).
    ///
    /// - Parameters:
    ///   - current: the desktop you're on. If it isn't in the grid (for
    ///     example you're on a fullscreen app), any direction goes to the
    ///     first desktop of the grid.
    ///   - rows: the grid, already filtered to desktops that can be switched to.
    static func target(from current: String?,
                       direction: NavDirection,
                       rows rawRows: [[String]],
                       rules: NavigationRules) -> String? {
        let rows = rawRows.filter { !$0.isEmpty }
        guard !rows.isEmpty else { return nil }

        guard let current = current, let pos = position(of: current, in: rows) else {
            return rows[0][0]
        }

        let row = rows[pos.row]
        var result: String?

        switch direction {
        case .left, .right:
            let step = direction == .left ? -1 : 1
            var column = pos.column + step
            if column < 0 || column >= row.count {
                guard rules.wrapHorizontally else { return nil }
                column = (column + row.count) % row.count
            }
            result = row[column]

        case .up, .down:
            let step = direction == .up ? -1 : 1
            var r = pos.row + step
            if r < 0 || r >= rows.count {
                guard rules.wrapVertically else { return nil }
                r = (r + rows.count) % rows.count
            }
            let destination = rows[r]
            let column: Int
            switch rules.verticalLanding {
            case .firstOfRow: column = 0
            case .sameColumn: column = min(pos.column, destination.count - 1)
            }
            result = destination[column]
        }

        return result == current ? nil : result
    }

    static func position(of key: String, in rows: [[String]]) -> GridPosition? {
        for (r, row) in rows.enumerated() {
            if let c = row.firstIndex(of: key) { return GridPosition(row: r, column: c) }
        }
        return nil
    }
}
