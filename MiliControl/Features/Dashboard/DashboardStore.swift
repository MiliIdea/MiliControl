//
//  DashboardStore.swift
//  MiliControl
//
//  Calendar data for the grid editor's dashboard: upcoming events and the
//  month's busy days, read through EventKit — the same accounts (iCloud,
//  Google, Exchange…) the Calendar app shows.
//
//  macOS doesn't let apps embed Apple's own widgets, so the dashboard draws
//  its own panels from this data. Nothing leaves the Mac.
//
//  Data is only fetched while the editor is on screen (and whenever Calendar
//  changes during that time).
//

import AppKit
import Combine
import EventKit
import SwiftUI

/// Whether MiliControl may read your calendars.
enum DashboardAccess {
    case notDetermined
    case granted
    /// Denied, restricted, or write-only — the user has to change it in
    /// System Settings.
    case denied
}

struct DashboardEvent: Identifiable, Equatable {
    let id: String
    let title: String
    /// Start of the day it's listed under (today or tomorrow).
    let day: Date
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
}

final class DashboardStore: ObservableObject {

    @Published private(set) var eventsAccess: DashboardAccess = .notDetermined
    /// Remaining events of today, then tomorrow's, in start order.
    @Published private(set) var events: [DashboardEvent] = []
    /// Every event of the current month, by the start of each day it covers
    /// (for the month panel's dots and hover list).
    @Published private(set) var monthEvents: [Date: [DashboardEvent]] = [:]

    /// MiliControl's own to-do list (not from Reminders).
    let todos = TodoStore()

    private let prefs: Preferences
    private let store = EKEventStore()
    private var isActive = false
    private var cancellables = Set<AnyCancellable>()

    init(prefs: Preferences) {
        self.prefs = prefs
        refreshAccess()

        // Edits in Calendar (or synced from another device).
        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, self.isActive else { return }
                self.reload()
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle (driven by the grid editor)

    func activate() {
        isActive = true
        refreshAccess()
        reload()
    }

    func deactivate() {
        isActive = false
    }

    /// Re-reads permission state (e.g. after a visit to System Settings).
    func refreshAccess() {
        eventsAccess = Self.access(for: .event)
    }

    // MARK: - Permission

    /// Shows macOS's permission prompt; `done` gets whether access was granted.
    func requestAccess(to type: EKEntityType, done: ((Bool) -> Void)? = nil) {
        let completion: (Bool, Error?) -> Void = { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.refreshAccess()
                if self?.isActive == true { self?.reload() }
                done?(granted)
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: completion)
        } else {
            store.requestAccess(to: type, completion: completion)
        }
    }

    private static func access(for type: EKEntityType) -> DashboardAccess {
        let status = EKEventStore.authorizationStatus(for: type)
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted, .denied: return .denied
        default:
            if #available(macOS 14.0, *) {
                return status == .fullAccess ? .granted : .denied   // write-only can't read
            }
            return .granted
        }
    }

    /// System Settings ▸ Privacy & Security ▸ Calendars.
    static func privacySettingsURL(for type: EKEntityType) -> URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
    }

    // MARK: - Loading

    func reload() {
        loadEvents()
        loadMonthEvents()
    }

    private static func makeEvent(_ event: EKEvent, day: Date) -> DashboardEvent {
        DashboardEvent(id: (event.eventIdentifier ?? UUID().uuidString) + "@\(day.timeIntervalSince1970)",
                       title: event.title?.isEmpty == false ? event.title! : "Untitled",
                       day: day,
                       start: event.startDate,
                       end: event.endDate,
                       isAllDay: event.isAllDay,
                       color: Color(cgColor: event.calendar.cgColor))
    }

    /// All-day first, then by start time.
    private static func eventOrder(_ a: DashboardEvent, _ b: DashboardEvent) -> Bool {
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        return a.start < b.start
    }

    private func loadMonthEvents() {
        let calendar = Calendar.current
        guard eventsAccess == .granted,
              let month = calendar.dateInterval(of: .month, for: Date()) else { monthEvents = [:]; return }
        let predicate = store.predicateForEvents(withStart: month.start, end: month.end, calendars: nil)
        var buckets: [Date: [DashboardEvent]] = [:]
        for event in store.events(matching: predicate) where event.status != .canceled {
            // Put the event on every day it covers (within this month).
            var day = calendar.startOfDay(for: max(event.startDate, month.start))
            let last = min(event.endDate, month.end)
            repeat {
                buckets[day, default: []].append(Self.makeEvent(event, day: day))
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            } while day < last
        }
        monthEvents = buckets.mapValues { $0.sorted(by: Self.eventOrder) }
    }

    private func loadEvents() {
        guard eventsAccess == .granted else { events = []; return }
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        guard let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday) else { return }
        let predicate = store.predicateForEvents(withStart: startOfToday, end: endOfTomorrow, calendars: nil)
        // The day an event shows under (multi-day events that began earlier show today).
        func day(_ event: EKEvent) -> Date { calendar.startOfDay(for: max(event.startDate, startOfToday)) }
        events = store.events(matching: predicate)
            .filter { $0.endDate > now && $0.status != .canceled }
            .map { Self.makeEvent($0, day: day($0)) }
            .sorted { a, b in a.day != b.day ? a.day < b.day : Self.eventOrder(a, b) }
            .prefix(30)
            .map { $0 }
    }
}
