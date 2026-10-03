import Foundation
import SwiftData

/// Keeps stored slots in line with settings and lazily marks expired slots as `missed`.
@MainActor
struct SlotResolver {
    let context: ModelContext

    func slots(ownerID: String) -> [CheckInSlot] {
        let descriptor = FetchDescriptor<CheckInSlot>(
            predicate: #Predicate<CheckInSlot> { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.scheduledAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Creates any slots due from the user's creation day through today, applies settings
    /// changes to today's slots (see `SlotPlanner.todaySpecs`), and marks pending slots past
    /// their grace window as missed.
    /// Returns all of the user's slots.
    @discardableResult
    func reconcile(user: LocalUser, settings: AppSettings, now: Date = .now) -> [CheckInSlot] {
        let timeZone = user.timeZone
        let grace = settings.graceMinutes
        let todayKey = DayKey.string(for: now, in: timeZone)

        var existing = Dictionary(slots(ownerID: user.id).map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let fromSettings = SlotPlanner.specs(from: user.createdAt, through: now, slotTimes: settings.slotTimes, timeZone: timeZone)
        let today = SlotPlanner.todaySpecs(
            settings: fromSettings.filter { $0.key.dayKey == todayKey },
            existing: existing.values.filter { $0.dayKey == todayKey }.map(\.snapshot)
        )
        // A past day that already has slots is complete; only days never reconciled are filled in.
        let storedDays = Set(existing.values.map(\.dayKey))
        let pastDays = fromSettings.filter { $0.key.dayKey != todayKey && !storedDays.contains($0.key.dayKey) }

        for spec in pastDays + today {
            if let slot = existing[spec.key] {
                if slot.scheduledAt != spec.scheduledAt {
                    slot.scheduledAt = spec.scheduledAt
                }
            } else if SlotRules.deadline(for: spec.scheduledAt, graceMinutes: grace) > user.createdAt {
                // Slots that had already closed before the user existed are never created.
                let slot = CheckInSlot(ownerID: user.id, dayKey: spec.key.dayKey, slotIndex: spec.key.slotIndex, scheduledAt: spec.scheduledAt)
                context.insert(slot)
                existing[spec.key] = slot
            }
        }

        let todayKeys = Set(today.map(\.key))
        for slot in existing.values where slot.dayKey == todayKey && !todayKeys.contains(slot.key) {
            context.delete(slot)
            existing[slot.key] = nil
        }

        for slot in existing.values where SlotRules.resolvedState(slot.snapshot, now: now, graceMinutes: grace) != slot.state {
            slot.state = .missed
            slot.resolvedAt = SlotRules.deadline(for: slot.scheduledAt, graceMinutes: grace)
            slot.synced = false
        }

        try? context.save()
        return existing.values.sorted { $0.scheduledAt < $1.scheduledAt }
    }
}
