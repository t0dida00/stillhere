import Foundation

struct SlotKey: Hashable, Codable, Identifiable {
    var dayKey: String
    var slotIndex: Int

    var id: String { "\(dayKey)#\(slotIndex)" }
}

/// A slot that should exist, derived from settings.
struct SlotSpec: Equatable {
    var key: SlotKey
    var scheduledAt: Date
}

/// Value copy of a stored slot, used by pure logic and tests.
struct SlotSnapshot: Equatable {
    var key: SlotKey
    var scheduledAt: Date
    var state: SlotState
}

enum DayKey {
    static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    static func string(for date: Date, in timeZone: TimeZone) -> String {
        let parts = calendar(in: timeZone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Start of the day named by `key` in `timeZone`.
    static func date(from key: String, in timeZone: TimeZone) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar(in: timeZone).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// "2026-10-02" → "02/10/2026" for display.
    static func display(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3 else { return key }
        return "\(parts[2])/\(parts[1])/\(parts[0])"
    }

    /// The key `days` days after `key` (negative goes back).
    static func adding(_ days: Int, to key: String) -> String? {
        let utc = TimeZone(identifier: "UTC")!
        guard let date = date(from: key, in: utc),
              let shifted = calendar(in: utc).date(byAdding: .day, value: days, to: date) else { return nil }
        return string(for: shifted, in: utc)
    }
}

enum SlotPlanner {
    static let minutesPerDay = 24 * 60

    /// Sorted, de-duplicated slot times within a single day.
    static func normalized(_ slotTimes: [Int]) -> [Int] {
        Array(Set(slotTimes.filter { (0..<minutesPerDay).contains($0) })).sorted()
    }

    static func specs(forDayContaining date: Date, slotTimes: [Int], timeZone: TimeZone) -> [SlotSpec] {
        let calendar = DayKey.calendar(in: timeZone)
        let day = calendar.startOfDay(for: date)
        let dayKey = DayKey.string(for: day, in: timeZone)
        return normalized(slotTimes).enumerated().compactMap { index, minutes in
            // bySettingHour handles DST shifts instead of adding raw minutes to midnight.
            guard let at = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) else { return nil }
            return SlotSpec(key: SlotKey(dayKey: dayKey, slotIndex: index), scheduledAt: at)
        }
    }

    /// Today's slots once settings change. Before anything today is resolved, `settings` applies as is.
    /// After that, slots up to the last resolved one keep their time and index, and the times in
    /// `settings` that come later follow with fresh indexes so keys never collide.
    static func todaySpecs(settings: [SlotSpec], existing: [SlotSnapshot]) -> [SlotSpec] {
        guard let anchor = existing.filter({ $0.state != .pending }).max(by: { $0.scheduledAt < $1.scheduledAt }) else {
            return settings
        }
        let kept = existing
            .filter { $0.scheduledAt <= anchor.scheduledAt }
            .sorted { $0.scheduledAt < $1.scheduledAt }
            .map { SlotSpec(key: $0.key, scheduledAt: $0.scheduledAt) }
        let nextIndex = (kept.map(\.key.slotIndex).max() ?? -1) + 1
        let added = settings
            .filter { $0.scheduledAt > anchor.scheduledAt }
            .enumerated()
            .map { offset, spec in
                SlotSpec(key: SlotKey(dayKey: anchor.key.dayKey, slotIndex: nextIndex + offset), scheduledAt: spec.scheduledAt)
            }
        return kept + added
    }

    /// Specs for every local day from the day containing `start` through the day containing `end`.
    static func specs(from start: Date, through end: Date, slotTimes: [Int], timeZone: TimeZone) -> [SlotSpec] {
        let calendar = DayKey.calendar(in: timeZone)
        var day = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)
        var result: [SlotSpec] = []
        while day <= lastDay {
            result += specs(forDayContaining: day, slotTimes: slotTimes, timeZone: timeZone)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}

enum SlotRules {
    static func deadline(for scheduledAt: Date, graceMinutes: Int) -> Date {
        scheduledAt.addingTimeInterval(TimeInterval(graceMinutes * 60))
    }

    /// A slot can be checked in while it is pending and inside its grace window.
    static func isOpen(_ slot: SlotSnapshot, now: Date, graceMinutes: Int) -> Bool {
        slot.state == .pending
            && slot.scheduledAt <= now
            && now < deadline(for: slot.scheduledAt, graceMinutes: graceMinutes)
    }

    /// Pending slots whose grace window has elapsed become `missed`; everything else is unchanged.
    static func resolvedState(_ slot: SlotSnapshot, now: Date, graceMinutes: Int) -> SlotState {
        guard slot.state == .pending else { return slot.state }
        return now >= deadline(for: slot.scheduledAt, graceMinutes: graceMinutes) ? .missed : .pending
    }
}

/// When partners are told about missed check-ins (SPEC §9). The server applies the same rule;
/// the app uses it to show a run of misses on a partner's calendar.
enum MissedAlertRule {
    /// Misses in a row that trigger the first alert.
    static let threshold = 2

    enum Alert: Equatable {
        /// The run just reached `threshold`.
        case missedInARow(Int)
        /// The run grew past what partners were already told.
        case stillMissing(Int)
        /// A check-in or skip ended a run that partners were alerted about.
        case allGood
    }

    /// Misses at the end of `slots`, by scheduled time and across days. Pending slots are
    /// ignored, since they haven't been decided yet; a check-in or skip ends the run.
    static func consecutiveMisses(_ slots: [SlotSnapshot]) -> Int {
        var count = 0
        for slot in slots.filter({ $0.state != .pending }).sorted(by: { $0.scheduledAt > $1.scheduledAt }) {
            guard slot.state == .missed else { break }
            count += 1
        }
        return count
    }

    /// The alert to send now, given the current run and the run length partners were last told about.
    static func alert(run: Int, alreadyAlerted: Int) -> Alert? {
        if run == 0 { return alreadyAlerted >= threshold ? .allGood : nil }
        guard run >= threshold, run > alreadyAlerted else { return nil }
        return alreadyAlerted < threshold ? .missedInARow(run) : .stillMissing(run)
    }
}
