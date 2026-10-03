import CoreLocation
import Foundation
import SwiftData

/// Check-in actions: reconcile slots, keep notifications in sync, and record outcomes.
@MainActor
struct CheckInService {
    let context: ModelContext
    var notifications: NotificationService = .shared
    var location: LocationService = .shared

    /// Reconciles slots and reschedules reminders. Returns the slot open for check-in, preferring `preferred`.
    @discardableResult
    func refresh(preferring preferred: SlotKey? = nil, now: Date = .now) async -> SlotKey? {
        let open = openSlot(preferring: preferred, now: now)
        await reschedule(now: now)
        return open
    }

    /// Reconciles slots and returns the slot open for check-in, preferring `preferred`.
    /// Local and quick, so the puzzle can show before `reschedule` finishes.
    func openSlot(preferring preferred: SlotKey? = nil, now: Date = .now) -> SlotKey? {
        guard let user = context.fetchUser() else { return nil }
        let settings = context.fetchOrCreateSettings()
        let slots = SlotResolver(context: context).reconcile(user: user, settings: settings, now: now)
        let open = slots.filter { SlotRules.isOpen($0.snapshot, now: now, graceMinutes: settings.graceMinutes) }
        if let preferred, open.contains(where: { $0.key == preferred }) {
            return preferred
        }
        return open.first?.key
    }

    /// Rebuilds alarms and notifications from the reconciled slots. Slow: one system call per alarm and reminder.
    func reschedule(now: Date = .now) async {
        guard let user = context.fetchUser() else { return }
        let settings = context.fetchOrCreateSettings()
        let slots = SlotResolver(context: context).reconcile(user: user, settings: settings, now: now)

        let resolved = Set(slots.filter { $0.state != .pending }.map(\.key))
        let todayKey = DayKey.string(for: now, in: user.timeZone)
        let today = slots.filter { $0.dayKey == todayKey }.map { SlotSpec(key: $0.key, scheduledAt: $0.scheduledAt) }
        var plan = NotificationPlanner.plan(
            now: now,
            slotTimes: settings.slotTimes,
            timeZone: user.timeZone,
            graceMinutes: settings.graceMinutes,
            remindEveryMinutes: settings.remindEveryMinutes,
            resolved: resolved,
            today: today
        )
        if #available(iOS 26.0, *) {
            let alarms = AlarmService.shared
            _ = await alarms.requestAuthorization()
            let upcoming = NotificationPlanner.upcomingSlots(now: now, slotTimes: settings.slotTimes, timeZone: user.timeZone, resolved: resolved, today: today)
            let withAlarm = await alarms.reschedule(upcoming)
            // The alarm replaces the slot-time notification; follow-up reminders stay.
            plan.removeAll { $0.sequence == 0 && withAlarm.contains($0.key) }
        }
        await notifications.reschedule(plan, now: now)
    }

    /// Saves where the app is being used, when location sharing is on and allowed.
    func recordLastLocation(now: Date = .now) async {
        guard let user = context.fetchUser(), context.fetchOrCreateSettings().shareLocation,
              let found = await location.currentLocation() else { return }
        user.lastLatitude = found.coordinate.latitude
        user.lastLongitude = found.coordinate.longitude
        user.lastLocationAt = now
        try? context.save()
        user.lastPlaceName = await location.placeName(for: found)
        try? context.save()
    }

    /// Adds an address to check-ins saved with only coordinates. A few per call, since
    /// address lookups are rate-limited.
    func backfillPlaceNames(limit: Int = 5) async {
        guard let user = context.fetchUser() else { return }
        let missing = SlotResolver(context: context).slots(ownerID: user.id)
            .filter { $0.placeName == nil && $0.latitude != nil && $0.longitude != nil }
            .suffix(limit)
        for slot in missing {
            guard let lat = slot.latitude, let lon = slot.longitude,
                  let name = await location.placeName(for: CLLocation(latitude: lat, longitude: lon)) else { continue }
            slot.placeName = name
        }
        try? context.save()
    }

    func slot(for key: SlotKey) -> CheckInSlot? {
        guard let user = context.fetchUser() else { return nil }
        return SlotResolver(context: context).slots(ownerID: user.id).first { $0.key == key }
    }

    /// Records a correct answer. Past the grace window the slot is recorded as missed instead.
    @discardableResult
    func checkIn(_ key: SlotKey, now: Date = .now) -> SlotState? {
        guard let slot = slot(for: key), slot.state == .pending else { return nil }
        let settings = context.fetchOrCreateSettings()
        let deadline = SlotRules.deadline(for: slot.scheduledAt, graceMinutes: settings.graceMinutes)
        let state: SlotState = now < deadline ? .checkedIn : .missed
        resolve(slot, as: state, at: state == .checkedIn ? now : deadline)

        if state == .checkedIn, settings.shareLocation {
            Task {
                guard let found = await location.currentLocation() else { return }
                slot.latitude = found.coordinate.latitude
                slot.longitude = found.coordinate.longitude
                try? context.save()
                slot.placeName = await location.placeName(for: found)
                try? context.save()
            }
        }
        return state
    }

    func skip(_ key: SlotKey, now: Date = .now) {
        guard let slot = slot(for: key), slot.state == .pending else { return }
        resolve(slot, as: .skipped, at: now)
    }

    private func resolve(_ slot: CheckInSlot, as state: SlotState, at date: Date) {
        slot.state = state
        slot.resolvedAt = date
        slot.synced = false
        try? context.save()
        let key = slot.key
        if #available(iOS 26.0, *) {
            AlarmService.shared.cancel(key)
        }
        Task { await notifications.cancel(key) }
    }
}
