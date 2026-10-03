import SwiftUI

struct CalendarView: View {
    @Binding var month: Date
    let timeZone: TimeZone
    let slotsByDay: [String: [DisplaySlot]]
    var onSelect: (String) -> Void

    private var calendar: Calendar { DayKey.calendar(in: timeZone) }

    var body: some View {
        let todayKey = DayKey.string(for: .now, in: timeZone)
        VStack(spacing: 12) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(monthTitle))
                    .font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let key = DayKey.string(for: date, in: timeZone)
                        DayCell(
                            day: calendar.component(.day, from: date),
                            states: (slotsByDay[key] ?? []).sorted { $0.scheduledAt < $1.scheduledAt }.map(\.state),
                            isToday: key == todayKey
                        )
                        .onTapGesture { onSelect(key) }
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }

            Legend()
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var monthTitle: Date.FormatStyle {
        var style = Date.FormatStyle().month(.wide).year()
        style.timeZone = timeZone
        return style
    }

    /// Very short weekday symbols, rotated so the locale's first weekday comes first.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Leading blanks for the first weekday offset, then each day of the month.
    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let dayCount = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let leading = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading)
            + (0..<dayCount).map { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private func shiftMonth(_ value: Int) {
        if let shifted = calendar.date(byAdding: .month, value: value, to: month) {
            month = shifted
        }
    }
}

private struct DayCell: View {
    let day: Int
    let states: [SlotState]
    let isToday: Bool

    private var isComplete: Bool { !states.isEmpty && done == states.count }
    private var hasMissed: Bool { states.contains(.missed) }
    private var done: Int { states.filter { $0 == .checkedIn || $0 == .skipped }.count }

    var body: some View {
        Text("\(day)")
            .font(.callout.weight(isToday || isComplete || hasMissed ? .bold : .regular))
            .foregroundStyle(isComplete || hasMissed ? Color.white : isToday ? Color.accentColor : Color.primary)
            .frame(width: 36, height: 36)
            .background { DayProgressRing(states: states) }
            .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day \(day): " + (states.isEmpty ? "no check-ins" : "\(done) of \(states.count) done; " + states.map(\.label).joined(separator: ", ")))
    }
}

/// An outer ring with one segment per slot in order (green = checked in, orange = skipped,
/// red = missed, empty = pending), around a fill once the day is decided: green when every slot
/// is checked in or skipped, red when any was missed.
struct DayProgressRing: View {
    let states: [SlotState]
    var lineWidth: CGFloat = 2.5
    /// Space between the ring and the fill.
    var gap: CGFloat = 2

    private var fill: Color? {
        if states.contains(.missed) { return .red }
        if !states.isEmpty, states.allSatisfy({ $0 == .checkedIn || $0 == .skipped }) { return .green }
        return nil
    }

    var body: some View {
        if !states.isEmpty, fill != nil || states.contains(where: { $0 != .pending }) {
            ZStack {
                if let fill {
                    Circle().fill(fill).padding(lineWidth + gap)
                }
                ring.padding(lineWidth / 2)
            }
        }
    }

    private var ring: some View {
        let share = 1 / CGFloat(states.count)
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: lineWidth)
            ForEach(Array(states.enumerated()), id: \.offset) { index, state in
                if let color = Self.color(for: state) {
                    Circle()
                        .trim(from: CGFloat(index) * share, to: CGFloat(index + 1) * share)
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                }
            }
            .rotationEffect(.degrees(-90))
        }
    }

    private static func color(for state: SlotState) -> Color? {
        switch state {
        case .checkedIn: .green
        case .skipped: .orange
        case .missed: .red
        case .pending: nil
        }
    }
}

/// Filled green = checked in, filled red = missed (high signal), hollow orange = skipped, hollow grey = pending.
struct SlotMarker: View {
    let state: SlotState
    var size: CGFloat = 7

    var body: some View {
        Group {
            switch state {
            case .checkedIn: Circle().fill(.green)
            case .missed: Circle().fill(.red)
            case .skipped: Circle().strokeBorder(.orange, lineWidth: max(1.5, size / 5))
            case .pending: Circle().strokeBorder(.secondary, lineWidth: max(1, size / 7))
            }
        }
        .frame(width: size, height: size)
    }
}

private struct Legend: View {
    private static let items: [(String, [SlotState])] = [
        ("Checked in", [.checkedIn, .checkedIn]),
        ("Skipped", [.skipped, .pending]),
        ("Missed", [.missed]),
        ("In progress", [.checkedIn, .pending]),
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Self.items, id: \.0) { label, states in
                HStack(spacing: 4) {
                    DayProgressRing(states: states, lineWidth: 1.5, gap: 1).frame(width: 14, height: 14)
                    Text(label)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
