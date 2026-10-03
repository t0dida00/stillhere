import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    /// Time-sensitive delivery comes from the entitlement plus `interruptionLevel`; there is no separate auth option.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces every pending slot reminder with `plan`.
    func reschedule(_ plan: [PlannedReminder], now: Date = .now) async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("slot.") })

        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = "StillAlive?"
            content.body = reminder.sequence == 0
                ? String(localized: "Time to check in. Solve a quick puzzle to let them know you're okay.")
                : String(localized: "Reminder: you haven't checked in yet.")
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.threadIdentifier = reminder.key.id
            content.userInfo = reminder.key.userInfo

            let interval = max(1, reminder.fireDate.timeIntervalSince(now))
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
        }
    }

    /// Tells me a partner missed a check-in. Tapping it opens their calendar.
    func notifyPartnerMissed(partnerID: String, name: String, slot: RemoteSlot, timeZone: TimeZone) async {
        var time = Date.FormatStyle(date: .omitted, time: .shortened)
        time.timeZone = timeZone
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(name) missed a check-in")
        content.body = String(localized: "The \(slot.scheduledAt.formatted(time)) check-in on \(DayKey.display(slot.dayKey)) wasn't done.")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "partner.\(partnerID)"
        let identifier = AlertRecord.identifier(partnerID: partnerID, dayKey: slot.dayKey, slotIndex: slot.slotIndex)
        content.userInfo = ["partnerID": partnerID, "alertID": identifier]
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    /// Removes the remaining reminders (pending and delivered) for a resolved slot.
    func cancel(_ key: SlotKey) async {
        let prefix = PlannedReminder.identifierPrefix(for: key)
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(prefix) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }
}

extension SlotKey {
    var userInfo: [String: Any] { ["dayKey": dayKey, "slotIndex": slotIndex] }

    init?(userInfo: [AnyHashable: Any]) {
        guard let dayKey = userInfo["dayKey"] as? String, let slotIndex = userInfo["slotIndex"] as? Int else { return nil }
        self.init(dayKey: dayKey, slotIndex: slotIndex)
    }
}
