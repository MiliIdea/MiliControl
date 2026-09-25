//
//  TodoStore.swift
//  MiliControl
//
//  MiliControl's own to-do list for the dashboard. Items live in
//  MiliControl's settings on this Mac (nothing syncs or leaves it).
//
//  Ticking an item off doesn't delete it straight away: it's marked done for
//  a couple of seconds — long enough to undo — and then removed.
//

import Foundation
import SwiftUI

struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let created: Date
}

final class TodoStore: ObservableObject {

    @Published private(set) var items: [TodoItem] = []
    /// Ticked off, waiting to be removed (undo possible until then).
    @Published private(set) var completing: Set<UUID> = []

    /// How long a ticked-off item stays, with Undo, before it goes.
    static let undoWindow: TimeInterval = 2

    private let defaults: UserDefaults
    private static let storageKey = "dashboard.todos.v1"
    private var removals: [UUID: DispatchWorkItem] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([TodoItem].self, from: data) {
            items = saved
        }
    }

    /// Items not yet ticked off.
    var openCount: Int { items.filter { !completing.contains($0.id) }.count }

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            items.append(TodoItem(id: UUID(), title: trimmed, created: Date()))
        }
        save()
    }

    /// Ticks an item off; it disappears after `undoWindow` unless undone.
    func complete(_ item: TodoItem) {
        guard !completing.contains(item.id) else { return }
        withAnimation(.easeOut(duration: 0.2)) { _ = completing.insert(item.id) }
        let removal = DispatchWorkItem { [weak self] in self?.remove(item.id) }
        removals[item.id] = removal
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.undoWindow, execute: removal)
    }

    func undo(_ item: TodoItem) {
        removals.removeValue(forKey: item.id)?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { _ = completing.remove(item.id) }
    }

    private func remove(_ id: UUID) {
        removals[id] = nil
        withAnimation(.easeInOut(duration: 0.35)) {
            items.removeAll { $0.id == id }
            completing.remove(id)
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: Self.storageKey) }
    }
}
