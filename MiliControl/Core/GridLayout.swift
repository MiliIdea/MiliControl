//
//  GridLayout.swift
//  MiliControl
//
//  The user's custom arrangement of desktops into rows. Rows may have
//  different lengths. Desktops are referenced by a stable string key (see
//  `DesktopStore`), never by position, so the layout survives desktops being
//  added or removed.
//
//  Pure Foundation — no AppKit — so it is unit-testable with `swift test`.
//

import Foundation

struct GridPosition: Equatable, Hashable {
    var row: Int
    var column: Int
}

struct GridLayout: Codable, Equatable {

    /// Rows of desktop keys, top to bottom, each left to right.
    private(set) var rows: [[String]]
    /// One name per row, parallel to `rows`. "" means unnamed ("Row N").
    private(set) var rowNames: [String]

    init(rows: [[String]] = [], rowNames: [String] = []) {
        self.rows = rows
        self.rowNames = rowNames
        normalizeNames()
    }

    private enum CodingKeys: String, CodingKey { case rows, rowNames }

    /// Also reads layouts saved before rows had names.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rows = try container.decode([[String]].self, forKey: .rows)
        rowNames = try container.decodeIfPresent([String].self, forKey: .rowNames) ?? []
        normalizeNames()
    }

    /// Keeps exactly one name per row.
    private mutating func normalizeNames() {
        if rowNames.count < rows.count {
            rowNames += Array(repeating: "", count: rows.count - rowNames.count)
        } else if rowNames.count > rows.count {
            rowNames = Array(rowNames.prefix(rows.count))
        }
    }

    // MARK: - Row names

    /// The user's name for a row, or nil if it's unnamed / blank.
    func name(ofRow index: Int) -> String? {
        guard rowNames.indices.contains(index) else { return nil }
        let trimmed = rowNames[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The name to show: the user's name, or "Row N".
    func displayName(ofRow index: Int) -> String {
        name(ofRow: index) ?? "Row \(index + 1)"
    }

    /// Raw text of a row's name (for editing). "" when unnamed.
    func rawName(ofRow index: Int) -> String {
        rowNames.indices.contains(index) ? rowNames[index] : ""
    }

    mutating func renameRow(_ index: Int, to name: String) {
        guard rowNames.indices.contains(index) else { return }
        rowNames[index] = name
    }

    /// A starting layout: the desktops in system order, `perRow` per row.
    static func chunked(_ keys: [String], perRow: Int = 4) -> GridLayout {
        let size = max(1, perRow)
        let rows = stride(from: 0, to: keys.count, by: size).map {
            Array(keys[$0 ..< min($0 + size, keys.count)])
        }
        return GridLayout(rows: rows.isEmpty ? [[]] : rows)
    }

    // MARK: - Queries

    var allKeys: [String] { rows.flatMap { $0 } }

    var isEmpty: Bool { allKeys.isEmpty }

    func position(of key: String) -> GridPosition? {
        for (r, row) in rows.enumerated() {
            if let c = row.firstIndex(of: key) { return GridPosition(row: r, column: c) }
        }
        return nil
    }

    func key(at position: GridPosition) -> String? {
        guard rows.indices.contains(position.row),
              rows[position.row].indices.contains(position.column) else { return nil }
        return rows[position.row][position.column]
    }

    // MARK: - Reconciliation

    /// Brings the layout in line with the spaces that actually exist:
    ///   • keys that no longer exist are removed — unless `retaining` says to
    ///     keep them (a fullscreen app that's out of fullscreen keeps its slot
    ///     for when it comes back);
    ///   • everything else stays exactly where the user put it;
    ///   • brand-new keys are added in `liveKeys` order: those matching
    ///     `besideNeighbor` right after the nearest earlier key (a new
    ///     fullscreen app appears next to the desktop it came from), the rest
    ///     at the end of the last row.
    /// Duplicate keys are collapsed to their first slot.
    func reconciled(with liveKeys: [String],
                    retaining: (String) -> Bool = { _ in false },
                    besideNeighbor: (String) -> Bool = { _ in false }) -> GridLayout {
        let live = Set(liveKeys)
        var seen = Set<String>()
        var newRows: [[String]] = rows.map { row in
            row.filter { key in
                guard live.contains(key) || retaining(key), !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
        }
        if newRows.isEmpty { newRows = [[]] }

        for (index, key) in liveKeys.enumerated() where !seen.contains(key) {
            seen.insert(key)
            if besideNeighbor(key),
               let neighbor = liveKeys[..<index].last(where: { seen.contains($0) }),
               let row = newRows.firstIndex(where: { $0.contains(neighbor) }),
               let column = newRows[row].firstIndex(of: neighbor) {
                newRows[row].insert(key, at: column + 1)
            } else {
                newRows[newRows.count - 1].append(key)
            }
        }
        return GridLayout(rows: newRows, rowNames: rowNames)
    }

    // MARK: - Native order

    /// The same rows, each sorted by `order` (macOS's desktop number), so
    /// moving right in a row always slides the way macOS animates it. Rows
    /// keep their members; only the order inside each row changes. Keys
    /// without an order keep their relative place at the end of the row.
    func sortedWithinRows(by order: (String) -> Int?) -> GridLayout {
        let sorted = rows.map { row -> [String] in
            row.enumerated()
                .sorted { a, b in
                    switch (order(a.element), order(b.element)) {
                    case let (x?, y?): return x != y ? x < y : a.offset < b.offset
                    case (.some, nil): return true
                    case (nil, .some): return false
                    case (nil, nil): return a.offset < b.offset
                    }
                }
                .map(\.element)
        }
        return GridLayout(rows: sorted, rowNames: rowNames)
    }

    // MARK: - Editing

    /// Moves `key` so that it ends up at `index` in `row` (the final index,
    /// clamped to the row's bounds; pass `Int.max` to append). If the key
    /// isn't in the layout yet it is inserted. Missing rows are created.
    mutating func move(_ key: String, toRow row: Int, index: Int) {
        guard row >= 0 else { return }
        if let from = position(of: key) { rows[from.row].remove(at: from.column) }
        while rows.count <= row { rows.append([]); rowNames.append("") }
        let target = max(0, min(index, rows[row].count))
        rows[row].insert(key, at: target)
    }

    /// Appends an empty, unnamed row at the bottom.
    mutating func addRow() {
        rows.append([])
        rowNames.append("")
    }

    /// Removes a row. Its desktops are never lost: they move to the end of the
    /// row above (or the row below, when removing the first row). The last
    /// remaining row cannot be removed.
    mutating func removeRow(at index: Int) {
        guard rows.count > 1, rows.indices.contains(index) else { return }
        let orphans = rows.remove(at: index)
        rowNames.remove(at: index)
        guard !orphans.isEmpty else { return }
        let destination = index > 0 ? index - 1 : 0
        rows[destination].append(contentsOf: orphans)
    }
}
