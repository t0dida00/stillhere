import Foundation

struct PlannedReminder: Equatable {
    var key: SlotKey
    var fireDate: Date
    /// 0 is the slot-time notification, 1... are follow-up reminders.
    var sequence: Int

    static func identifierPrefix(for key: SlotKey) -> String { "slot.\(key.id)." }

    var identifier: String { Self.identifierPrefix(for: key) + String(sequence) }
}

enum NotificationPlanner {
    /// iOS keeps at most 64 pending local notifications; leave headroom.
    static let maxPending = 60

    /// Reminders for the next `days` days, soonest first, capped at `limit`.
    static func plan(
        now: Date,
        days: Int = 7,
        slotTimes: [Int],
        timeZone: TimeZone,
        graceMinutes: Int,
        remindEveryMinutes: Int,
        resolved: Set<SlotKey>,
        today: [SlotSpec]? = nil,
        limit: Int = maxPending
    ) -> [PlannedReminder] {
        let step = max(1, remindEveryMinutes)

        var reminders: [PlannedReminder] = []
        for spec in specs(now: now, days: days, slotTimes: slotTimes, timeZone: timeZone, today: today)
        where !resolved.contains(spec.key) {
            for (sequence, offset) in stride(from: 0, to: max(1, graceMinutes), by: step).enumerated() {
                let fireDate = spec.scheduledAt.addingTimeInterval(TimeInterval(offset * 60))
                if fireDate > now {
                    reminders.append(PlannedReminder(key: spec.key, fireDate: fireDate, sequence: sequence))
                }
            }
        }
        return Array(reminders.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }

    /// Unresolved slots in the next `days` days whose time hasn't come yet, soonest first.
    static func upcomingSlots(now: Date, days: Int = 7, slotTimes: [Int], timeZone: TimeZone, resolved: Set<SlotKey>, today: [SlotSpec]? = nil) -> [SlotSpec] {
        specs(now: now, days: days, slotTimes: slotTimes, timeZone: timeZone, today: today)
            .filter { $0.scheduledAt > now && !resolved.contains($0.key) }
    }

    /// Slots from settings for the next `days` days. `today`, when given, replaces today's slots,
    /// since stored slots can differ from settings once something today is resolved.
    private static func specs(now: Date, days: Int, slotTimes: [Int], timeZone: TimeZone, today: [SlotSpec]?) -> [SlotSpec] {
        let calendar = DayKey.calendar(in: timeZone)
        guard let end = calendar.date(byAdding: .day, value: days - 1, to: now) else { return [] }
        let specs = SlotPlanner.specs(from: now, through: end, slotTimes: slotTimes, timeZone: timeZone)
        guard let today else { return specs }
        let todayKey = DayKey.string(for: now, in: timeZone)
        return today + specs.filter { $0.key.dayKey != todayKey }
    }
}
