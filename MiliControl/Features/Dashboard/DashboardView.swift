//
//  DashboardView.swift
//  MiliControl
//
//  The strip above the rows in the grid editor: clock & date, this month
//  (dots on days with events; hover a day to see them), Up Next (Calendar),
//  a to-do list and a sticky note. Panels share the full width; each can be
//  turned off in Settings ▸ Dashboard.
//

import SwiftUI
import AppKit
import EventKit

struct DashboardActions {
    let openCalendar: () -> Void
    /// Asks macOS for Calendar access.
    let requestAccess: (EKEntityType) -> Void
    /// Opens System Settings at the Calendars privacy list.
    let openPrivacySettings: (EKEntityType) -> Void
}

struct DashboardView: View {
    @ObservedObject var store: DashboardStore
    @ObservedObject var prefs: Preferences
    let height: CGFloat
    let actions: DashboardActions

    /// Whether any panel is turned on.
    static func hasPanels(_ prefs: Preferences) -> Bool {
        prefs.showDashboard
            && (prefs.dashboardClock || prefs.dashboardMonth || prefs.dashboardEvents
                || prefs.dashboardTodo || prefs.dashboardNote)
    }

    /// Panels share the full width equally, like a row of widgets.
    var body: some View {
        HStack(spacing: 16) {
            if prefs.dashboardClock {
                ClockPanel(style: prefs.clockStyle, secondary: prefs.secondaryCalendar, height: height)
                    .frame(minWidth: 220, maxWidth: .infinity)
            }
            if prefs.dashboardMonth {
                MonthPanel(store: store, secondary: prefs.secondaryCalendar, height: height,
                           open: actions.openCalendar)
                    .frame(minWidth: 330, maxWidth: .infinity)
                    .zIndex(1)          // its hover bubble floats over the neighbours
            }
            if prefs.dashboardEvents {
                EventsPanel(store: store, height: height, actions: actions)
                    .frame(minWidth: 200, maxWidth: .infinity)
            }
            if prefs.dashboardTodo {
                TodoPanel(todos: store.todos)
                    .frame(minWidth: 200, maxWidth: 290)
            }
            if prefs.dashboardNote {
                NotePanel(prefs: prefs)
                    .frame(minWidth: 180, maxWidth: .infinity)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Card

/// Shared panel chrome, matching the editor's row cards. Clicking the card's
/// background runs `onTap` (e.g. open Calendar) and never closes the editor.
private struct DashboardCard<Content: View>: View {
    var title: String?
    var trailing: String?
    /// For trailing text in another script (e.g. a Persian month name).
    var trailingFont: Font?
    var help: String?
    var onTap: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = title {
                HStack(spacing: 8) {
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.accentColor)
                    Spacer(minLength: 4)
                    if let trailing = trailing {
                        Text(trailing)
                            .font(trailingFont ?? .system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .onTapGesture { onTap?() }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .help(help ?? "")
    }
}

/// Space for list rows inside a card of the given height.
private func listRowCapacity(cardHeight: CGFloat, rowHeight: CGFloat) -> Int {
    let usable = cardHeight - 32 /* padding */ - 24 /* title */
    return max(1, Int(usable / rowHeight))
}

// MARK: - Clock & date

private struct ClockPanel: View {
    let style: ClockStyle
    let secondary: SecondaryCalendar
    let height: CGFloat

    var body: some View {
        DashboardCard {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                switch style {
                case .analog: analog(context.date)
                case .digital: digital(context.date)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Face and date side by side; the face never takes more than about half
    /// the width, so the date always fits on single lines.
    private func analog(_ date: Date) -> some View {
        GeometryReader { geometry in
            let face = min(geometry.size.height, geometry.size.width * 0.5)
            HStack(spacing: 16) {
                AnalogClockFace(date: date)
                    .frame(width: face, height: face)
                dateStack(date, dayFont: min(52, face * 0.36))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func digital(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            Text(date, format: .dateTime.hour().minute())
                .font(.system(size: min(64, height * 0.3), weight: .light).monospacedDigit())
            Text(date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            SecondaryDate(calendar: secondary, date: date, size: 14, topSpacing: 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }

    private func dateStack(_ date: Date, dayFont: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(date, format: .dateTime.weekday(.wide))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .textCase(.uppercase)
            Text(date, format: .dateTime.day())
                .font(.system(size: dayFont, weight: .bold, design: .rounded))
            Text(date, format: .dateTime.month(.wide).year())
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            SecondaryDate(calendar: secondary, date: date, size: 13, topSpacing: 6)
        }
        // One line each; shrink rather than wrap or truncate.
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// A plain analog watch face: ticks, hour/minute hands, accent second hand.
private struct AnalogClockFace: View {
    let date: Date

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func point(_ turn: Double, _ length: CGFloat) -> CGPoint {
                let angle = turn * 2 * .pi
                return CGPoint(x: center.x + CGFloat(sin(angle)) * length,
                               y: center.y - CGFloat(cos(angle)) * length)
            }
            func line(_ turn: Double, from inner: CGFloat, to outer: CGFloat,
                      width: CGFloat, color: Color) {
                var path = Path()
                path.move(to: point(turn, inner))
                path.addLine(to: point(turn, outer))
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: width, lineCap: .round))
            }

            // Face
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                width: radius * 2, height: radius * 2)),
                         with: .color(.white.opacity(0.08)))
            // Ticks
            for tick in 0 ..< 60 {
                let major = tick % 5 == 0
                line(Double(tick) / 60,
                     from: radius * (major ? 0.78 : 0.86), to: radius * 0.92,
                     width: radius * (major ? 0.035 : 0.012),
                     color: .white.opacity(major ? 0.85 : 0.3))
            }
            // Hands
            let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let seconds = Double(parts.second ?? 0)
            let minutes = Double(parts.minute ?? 0) + seconds / 60
            let hours = Double((parts.hour ?? 0) % 12) + minutes / 60
            line(hours / 12, from: 0, to: radius * 0.5, width: radius * 0.075, color: .white)
            line(minutes / 60, from: 0, to: radius * 0.74, width: radius * 0.05, color: .white)
            line(seconds / 60, from: -radius * 0.14, to: radius * 0.82, width: radius * 0.02, color: .accentColor)
            let dot = radius * 0.06
            context.fill(Path(ellipseIn: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2)),
                         with: .color(.accentColor))
        }
        .accessibilityLabel(Text(date, format: .dateTime.hour().minute()))
    }
}

// MARK: - Second calendar

/// Dates in the chosen second calendar, written in its own language.
enum CalendarText {
    private static var formatters: [String: DateFormatter] = [:]

    private static func formatter(_ calendar: SecondaryCalendar, _ template: String) -> DateFormatter? {
        let key = calendar.rawValue + "|" + template
        if let cached = formatters[key] { return cached }
        guard let system = calendar.calendar else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = system
        formatter.locale = calendar.locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        formatters[key] = formatter
        return formatter
    }

    /// A clean sans-serif face for the calendar's script. Persian and Arabic
    /// text would otherwise fall back to a calligraphic (naskh) face; see
    /// `AppFonts.persianFamilies` for the order tried.
    static func font(for calendar: SecondaryCalendar, size: CGFloat, weight: NSFont.Weight) -> Font {
        let arabicScript = calendar == .persian || calendar == .islamic
        if arabicScript, let sans = sansArabic(size: size, weight: weight) {
            return Font(sans)
        }
        return .system(size: size, weight: Font.Weight(weight))
    }

    private static var sansCache: [String: NSFont] = [:]

    private static func sansArabic(size: CGFloat, weight: NSFont.Weight) -> NSFont? {
        let key = "\(size)|\(weight.rawValue)"
        if let cached = sansCache[key] { return cached }
        // The bundled font, by exact face — no guessing at weights.
        if let bundled = AppFonts.vazirmatn(size: size, weight: weight) {
            sansCache[key] = bundled
            return bundled
        }
        for family in AppFonts.persianFamilies {
            let descriptor = NSFontDescriptor(fontAttributes: [
                .family: family,
                .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue],
            ])
            if let font = NSFont(descriptor: descriptor, size: size), font.familyName == family {
                sansCache[key] = font
                return font
            }
        }
        return nil
    }

    /// "جمعه ۳ مهر ۱۴۰۵"
    static func full(_ date: Date, in calendar: SecondaryCalendar) -> String {
        formatter(calendar, "EEEEdMMMMy")?.string(from: date) ?? ""
    }

    /// The day in the second calendar for a month-grid cell: its number
    /// ("۳"), or the month's short name on its first day ("مهر").
    static func dayLabel(_ date: Date, in calendar: SecondaryCalendar) -> (text: String, isMonthStart: Bool) {
        guard let system = calendar.calendar else { return ("", false) }
        let isMonthStart = system.component(.day, from: date) == 1
        let text = formatter(calendar, isMonthStart ? "MMM" : "d")?.string(from: date) ?? ""
        return (text, isMonthStart)
    }

    /// The second calendar's month(s) covering this Gregorian month:
    /// "شهریور – مهر ۱۴۰۵".
    static func monthRange(of date: Date, in calendar: SecondaryCalendar) -> String {
        let gregorian = Calendar.current
        guard let month = gregorian.dateInterval(of: .month, for: date),
              let last = gregorian.date(byAdding: .day, value: -1, to: month.end),
              let system = calendar.calendar,
              let withYear = formatter(calendar, "MMMMy"),
              let monthOnly = formatter(calendar, "MMMM") else { return "" }
        let first = month.start
        if system.isDate(first, equalTo: last, toGranularity: .month) {
            return withYear.string(from: last)
        }
        let sameYear = system.isDate(first, equalTo: last, toGranularity: .year)
        let start = sameYear ? monthOnly.string(from: first) : withYear.string(from: first)
        return "\(start) – \(withYear.string(from: last))"
    }
}

/// One line with today's date in the second calendar (nothing if none).
private struct SecondaryDate: View {
    let calendar: SecondaryCalendar
    let date: Date
    let size: CGFloat
    let topSpacing: CGFloat

    var body: some View {
        if calendar != .none {
            Text(CalendarText.full(date, in: calendar))
                .font(CalendarText.font(for: calendar, size: size, weight: .semibold))
                .foregroundStyle(Color.accentColor.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, topSpacing)
        }
    }
}

// MARK: - Month

private struct MonthPanel: View {
    @ObservedObject var store: DashboardStore
    let secondary: SecondaryCalendar
    let height: CGFloat
    let open: () -> Void
    /// The day under the pointer (start of day).
    @State private var hoveredDay: Date?

    var body: some View {
        // Refreshes each minute so "today" moves at midnight.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            DashboardCard(title: context.date.formatted(.dateTime.month(.wide)),
                          trailing: secondary == .none
                            ? context.date.formatted(.dateTime.year())
                            : CalendarText.monthRange(of: context.date, in: secondary),
                          trailingFont: secondary == .none ? nil : CalendarText.font(for: secondary, size: 11, weight: .semibold),
                          help: hoveredDay == nil ? "Click to open Calendar" : nil,
                          onTap: open) {
                MonthGrid(today: context.date, height: height - 32 - 24, secondary: secondary,
                          events: store.monthEvents, hoveredDay: $hoveredDay)
                    .overlayPreferenceValue(DayAnchorKey.self) { anchors in
                        GeometryReader { geometry in
                            bubble(anchors: anchors, in: geometry)
                        }
                    }
            }
        }
    }

    /// The hovered day's events, floating just below (or above) its cell.
    @ViewBuilder
    private func bubble(anchors: [Date: Anchor<CGRect>], in geometry: GeometryProxy) -> some View {
        if let day = hoveredDay, let anchor = anchors[day],
           let events = store.monthEvents[day], !events.isEmpty {
            let cell = geometry[anchor]
            let above = cell.midY > geometry.size.height / 2
            ZStack(alignment: .topLeading) {
                Color.clear
                DayEventsBubble(day: day, events: events)
                    .fixedSize()
                    .alignmentGuide(.leading) { $0.width / 2 }
                    .alignmentGuide(.top) { above ? $0.height : 0 }
                    .offset(x: cell.midX, y: above ? cell.minY - 6 : cell.maxY + 6)
                    .transition(.opacity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .allowsHitTesting(false)
        }
    }
}

/// Where the hovered day's cell is, so the bubble can sit next to it.
private struct DayAnchorKey: PreferenceKey {
    static var defaultValue: [Date: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Date: Anchor<CGRect>], nextValue: () -> [Date: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct MonthGrid: View {
    let today: Date
    let height: CGFloat
    /// Shown as a small second number under each day (e.g. the Shamsi date).
    let secondary: SecondaryCalendar
    let events: [Date: [DashboardEvent]]
    @Binding var hoveredDay: Date?

    var body: some View {
        let calendar = Calendar.current
        let weeks = Self.weeks(for: today, calendar: calendar)
        // The weekday row is shorter than a day row, so the days get more room.
        let cellHeight = height / (CGFloat(weeks.count) + 0.7)
        // A second calendar needs room for its line under each number.
        let fontSize = secondary == .none ? min(15, max(10, cellHeight * 0.56)) : min(14, max(10, cellHeight * 0.42))
        let todayNumber = calendar.component(.day, from: today)
        let monthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today

        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(Self.weekdaySymbols(calendar).enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: fontSize - 1, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: cellHeight * 0.7, maxHeight: cellHeight * 0.7)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                GridRow {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day = day,
                           let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                            dayCell(day, date: date, isToday: day == todayNumber,
                                    fontSize: fontSize, height: cellHeight)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: cellHeight, maxHeight: cellHeight)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Int, date: Date, isToday: Bool,
                         fontSize: CGFloat, height: CGFloat) -> some View {
        let dayEvents = events[date] ?? []
        let isHovered = hoveredDay == date && !dayEvents.isEmpty
        let showsSecondary = secondary != .none
        // Round for one number; a soft rounded tile when two are stacked.
        let highlight = RoundedRectangle(cornerRadius: showsSecondary ? height * 0.3 : height / 2,
                                         style: .continuous)
        let highlightWidth = showsSecondary ? height * 1.05 : height * 0.94
        return ZStack {
            if isToday {
                highlight.fill(Color.accentColor)
                    .frame(width: highlightWidth, height: height * 0.94)
            } else if isHovered {
                highlight.fill(Color.white.opacity(0.14))
                    .frame(width: highlightWidth, height: height * 0.94)
            }
            VStack(spacing: showsSecondary ? 1 : 1) {
                // Line boxes are pinned to the glyph size: fonts like Vazirmatn
                // carry tall line spacing that would otherwise squeeze the cell
                // and shrink the second number.
                Text("\(day)")
                    .font(.system(size: fontSize, weight: isToday ? .bold : .medium).monospacedDigit())
                    .foregroundStyle(isToday ? Color.white : Color.primary)
                    .frame(height: showsSecondary ? fontSize * 1.05 : nil)
                if showsSecondary {
                    let label = CalendarText.dayLabel(date, in: secondary)
                    let secondSize = max(11, fontSize * 0.85)
                    Text(label.text)
                        .font(CalendarText.font(for: secondary, size: secondSize,
                                                weight: label.isMonthStart ? .bold : .semibold))
                        .foregroundStyle(isToday ? Color.white.opacity(0.9)
                                         : label.isMonthStart ? Color.accentColor : Color.primary.opacity(0.6))
                        .lineLimit(1)
                        .fixedSize()
                        .frame(height: secondSize * 1.05)
                }
                // One dot per event (up to three), in its calendar's colour.
                HStack(spacing: 2) {
                    ForEach(Array(dayEvents.prefix(3).enumerated()), id: \.offset) { _, event in
                        Circle()
                            .fill(isToday ? Color.white : event.color)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) {
                if inside { hoveredDay = date } else if hoveredDay == date { hoveredDay = nil }
            }
        }
        .anchorPreference(key: DayAnchorKey.self, value: .bounds) { hoveredDay == date ? [date: $0] : [:] }
    }

    /// One-letter weekday names, starting on the locale's first weekday.
    private static func weekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The month as weeks of day numbers (nil = padding outside the month).
    private static func weeks(for date: Date, calendar: Calendar) -> [[Int?]] {
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let days = calendar.range(of: .day, in: .month, for: start)?.count else { return [] }
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        var cells: [Int?] = Array(repeating: nil, count: leading) + (1 ... days).map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0 ..< $0 + 7]) }
    }
}

// MARK: - Up Next (Calendar)

private struct EventsPanel: View {
    @ObservedObject var store: DashboardStore
    let height: CGFloat
    let actions: DashboardActions

    private enum Line: Identifiable {
        case header(String)
        case event(DashboardEvent)
        var id: String {
            switch self {
            case .header(let title): return "h-" + title
            case .event(let event): return event.id + "\(event.start.timeIntervalSince1970)"
            }
        }
    }

    var body: some View {
        DashboardCard(title: "Up Next", help: "Click to open Calendar", onTap: actions.openCalendar) {
            switch store.eventsAccess {
            case .notDetermined:
                PermissionPrompt(symbol: "calendar", message: "See today's events here.",
                                 button: "Allow Access") { actions.requestAccess(.event) }
            case .denied:
                PermissionPrompt(symbol: "calendar.badge.exclamationmark",
                                 message: "MiliControl can't read your calendars.",
                                 button: "Open Settings") { actions.openPrivacySettings(.event) }
            case .granted:
                if store.events.isEmpty {
                    EmptyNote(symbol: "checkmark.circle", message: "No more events today")
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(lines) { line in
                            switch line {
                            case .header(let title):
                                Text(title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            case .event(let event):
                                EventRow(event: event)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Today's events, then a "Tomorrow" header and tomorrow's — as many as fit.
    private var lines: [Line] {
        let capacity = listRowCapacity(cardHeight: height, rowHeight: 36)
        let today = Calendar.current.startOfDay(for: Date())
        var result: [Line] = []
        var shownTomorrow = false
        for event in store.events {
            if event.day > today && !shownTomorrow {
                if result.isEmpty { result.append(.header("Nothing else today · Tomorrow")) }
                else { result.append(.header("Tomorrow")) }
                shownTomorrow = true
            }
            result.append(.event(event))
            if result.count >= capacity { break }
        }
        if case .header? = result.last { result.removeLast() }
        return result
    }
}

private struct EventRow: View {
    let event: DashboardEvent

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.color)
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(timeText)
                    .font(.system(size: 11))
                    .foregroundStyle(isNow ? Color.accentColor : Color.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var isNow: Bool {
        let now = Date()
        return !event.isAllDay && event.start <= now && now < event.end
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        let end = event.end.formatted(date: .omitted, time: .shortened)
        if isNow { return "Now · until \(end)" }
        return "\(event.start.formatted(date: .omitted, time: .shortened)) – \(end)"
    }
}

// MARK: - To do

/// MiliControl's own to-do list: tick an item off and it fades out after a
/// couple of seconds, with an Undo meanwhile; type below to add one.
private struct TodoPanel: View {
    @ObservedObject var todos: TodoStore
    @State private var draft = ""
    @FocusState private var adding: Bool

    var body: some View {
        DashboardCard(title: "To Do",
                      trailing: todos.openCount > 0 ? "\(todos.openCount) left" : nil) {
            VStack(alignment: .leading, spacing: 6) {
                if todos.items.isEmpty {
                    EmptyNote(symbol: "checkmark.circle", message: "Nothing to do")
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(todos.items) { item in
                                TodoRow(item: item, isDone: todos.completing.contains(item.id),
                                        complete: { todos.complete(item) },
                                        undo: { todos.undo(item) })
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                                        removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .leading))))
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                // Add a task.
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(adding ? Color.accentColor : Color.secondary)
                        .frame(width: 18)
                    TextField("Add a task", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($adding)
                        .onSubmit {
                            todos.add(draft)
                            draft = ""
                            adding = true              // keep typing the next one
                        }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(adding ? 0.1 : 0.05)))
            }
        }
    }
}

private struct TodoRow: View {
    let item: TodoItem
    let isDone: Bool
    let complete: () -> Void
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: isDone ? undo : complete) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isDone ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                    .contentTransition(.symbolEffectIfAvailable)
            }
            .buttonStyle(.plain)
            .help(isDone ? "Not done" : "Mark as done")

            Text(item.title)
                .font(.system(size: 13))
                .strikethrough(isDone, color: .secondary)
                .foregroundStyle(isDone ? Color.secondary : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if isDone {
                Button("Undo", action: undo)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(height: 22)
        .opacity(isDone ? 0.7 : 1)
    }
}

private extension ContentTransition {
    /// The symbol morph where available (macOS 14), a plain cross-fade before.
    static var symbolEffectIfAvailable: ContentTransition {
        if #available(macOS 14.0, *) { return .symbolEffect(.replace) }
        return .opacity
    }
}

// MARK: - States

private struct PermissionPrompt: View {
    let symbol: String
    let message: String
    let button: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(button, action: action)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyNote: View {
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20))
            Text(message)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Month: hover bubble

/// The events of one day, shown while hovering its date.
private struct DayEventsBubble: View {
    let day: Date
    let events: [DashboardEvent]
    private let limit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 12, weight: .semibold))
            ForEach(events.prefix(limit)) { event in
                HStack(spacing: 7) {
                    Circle()
                        .fill(event.color)
                        .frame(width: 7, height: 7)
                    Text(time(for: event))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 62, alignment: .leading)
                    Text(event.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
            }
            if events.count > limit {
                Text("+\(events.count - limit) more")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
    }

    private func time(for event: DashboardEvent) -> String {
        // All-day, or a multi-day event continuing from an earlier day.
        if event.isAllDay || event.start < event.day { return "All day" }
        return event.start.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Sticky note

/// A yellow note in the top-right corner. Type anywhere in it; it's saved as
/// you go and stays until you change it.
private struct NotePanel: View {
    @ObservedObject var prefs: Preferences

    private let ink = Color(red: 0.22, green: 0.18, blue: 0.05)

    var body: some View {
        ZStack(alignment: .topLeading) {
            if prefs.noteText.isEmpty {
                Text("Jot something down…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ink.opacity(0.45))
                    .padding(.leading, 5)          // matches the text view's inset
                    .allowsHitTesting(false)
            }
            TextEditor(text: $prefs.noteText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(ink)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.93, blue: 0.55),
                                              Color(red: 0.98, green: 0.85, blue: 0.38)],
                                     startPoint: .top, endPoint: .bottom))
                .onTapGesture {}                   // clicks here never close the editor
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        // Dark caret and selection on the light paper.
        .environment(\.colorScheme, .light)
        .help("Saved automatically")
    }
}

private extension Font.Weight {
    init(_ weight: NSFont.Weight) {
        switch weight.rawValue {
        case ..<NSFont.Weight.light.rawValue: self = .thin
        case ..<NSFont.Weight.regular.rawValue: self = .light
        case ..<NSFont.Weight.medium.rawValue: self = .regular
        case ..<NSFont.Weight.semibold.rawValue: self = .medium
        case ..<NSFont.Weight.bold.rawValue: self = .semibold
        case ..<NSFont.Weight.heavy.rawValue: self = .bold
        default: self = .heavy
        }
    }
}
