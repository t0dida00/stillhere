import Foundation

struct Metrics: Equatable {
    /// Days on which every slot was checked in or skipped, with none missed.
    var checkedInDays: Int
    /// Consecutive checked-in days ending today (or yesterday while today is still in progress).
    var currentStreak: Int
    /// Total missed slots.
    var missedCount: Int
}

enum MetricsCalculator {
    static func compute(_ slots: [SlotSnapshot], todayKey: String) -> Metrics {
        let byDay = Dictionary(grouping: slots, by: \.key.dayKey)
        let isComplete: (String) -> Bool = { day in
            guard let daySlots = byDay[day], !daySlots.isEmpty else { return false }
            return daySlots.allSatisfy { $0.state == .checkedIn || $0.state == .skipped }
        }

        let checkedInDays = byDay.keys.filter(isComplete).count
        let missedCount = slots.filter { $0.state == .missed }.count

        var streak = 0
        var day: String? = todayKey
        if !isComplete(todayKey) {
            let today = byDay[todayKey] ?? []
            // Today still in progress doesn't break the streak; a miss does.
            if today.contains(where: { $0.state == .missed }) {
                return Metrics(checkedInDays: checkedInDays, currentStreak: 0, missedCount: missedCount)
            }
            day = DayKey.adding(-1, to: todayKey)
        }
        while let current = day, isComplete(current) {
            streak += 1
            day = DayKey.adding(-1, to: current)
        }
        return Metrics(checkedInDays: checkedInDays, currentStreak: streak, missedCount: missedCount)
    }
}
