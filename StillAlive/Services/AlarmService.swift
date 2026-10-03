import AlarmKit
import AppIntents
import CryptoKit
import OSLog
import SwiftUI

/// Full-screen alarms at each slot time (iOS 26+). They ring through silent mode and Focus;
/// follow-up reminders during the grace window stay as notifications.
@available(iOS 26.0, *)
@MainActor
final class AlarmService {
    static let shared = AlarmService()

    private let manager = AlarmManager.shared
    private let log = Logger(subsystem: "dev.khoa.stillalive", category: "alarms")

    var isAuthorized: Bool { manager.authorizationState == .authorized }

    /// Asks once; later calls return the stored answer.
    func requestAuthorization() async -> Bool {
        if manager.authorizationState == .notDetermined {
            _ = try? await manager.requestAuthorization()
        }
        return isAuthorized
    }

    private var lastReschedule: Task<Set<SlotKey>, Never>?

    /// Replaces every scheduled alarm with one per slot in `slots`. Returns the slots that got an alarm.
    /// Calls run one at a time; overlapping refreshes otherwise cancel each other's alarms.
    @discardableResult
    func reschedule(_ slots: [SlotSpec]) async -> Set<SlotKey> {
        let previous = lastReschedule
        let task = Task {
            _ = await previous?.value
            return await self.replaceAlarms(with: slots)
        }
        lastReschedule = task
        return await task.value
    }

    private func replaceAlarms(with slots: [SlotSpec]) async -> Set<SlotKey> {
        for alarm in (try? manager.alarms) ?? [] {
            try? manager.cancel(id: alarm.id)
        }
        guard isAuthorized else {
            log.notice("Not scheduling alarms: authorization is \(String(describing: self.manager.authorizationState))")
            return []
        }

        var scheduled: Set<SlotKey> = []
        for slot in slots {
            do {
                _ = try await manager.schedule(id: Self.alarmID(for: slot.key), configuration: configuration(for: slot))
                scheduled.insert(slot.key)
            } catch AlarmManager.AlarmError.maximumLimitReached {
                log.error("Alarm limit reached after \(scheduled.count) alarms")
                break
            } catch {
                log.error("Couldn't schedule alarm for \(slot.key.id): \(error)")
            }
        }
        log.notice("Scheduled \(scheduled.count) of \(slots.count) alarms; next at \(slots.first?.scheduledAt.description ?? "none")")
        return scheduled
    }

    func cancel(_ key: SlotKey) {
        try? manager.cancel(id: Self.alarmID(for: key))
    }

    /// Derived from the slot key so an alarm can be found again without storing its ID.
    nonisolated static func alarmID(for key: SlotKey) -> UUID {
        let bytes = Array(SHA256.hash(data: Data("stillalive.alarm.\(key.id)".utf8)).prefix(16))
        return UUID(uuid: bytes.withUnsafeBytes { $0.load(as: uuid_t.self) })
    }

    private func configuration(for slot: SlotSpec) -> AlarmManager.AlarmConfiguration<CheckInAlarmMetadata> {
        let checkIn = AlarmButton(text: "Check in", textColor: .white, systemImageName: "checkmark.circle.fill")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: "Time to check in", secondaryButton: checkIn, secondaryButtonBehavior: .custom)
        } else {
            let stop = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
            alert = AlarmPresentation.Alert(title: "Time to check in", stopButton: stop, secondaryButton: checkIn, secondaryButtonBehavior: .custom)
        }
        let attributes = AlarmAttributes<CheckInAlarmMetadata>(presentation: AlarmPresentation(alert: alert), tintColor: .accentColor)
        return .alarm(schedule: .fixed(slot.scheduledAt), attributes: attributes, secondaryIntent: OpenCheckInIntent(key: slot.key))
    }
}

@available(iOS 26.0, *)
struct CheckInAlarmMetadata: AlarmMetadata {}

/// The alarm's "Check in" button: stops the alarm and opens the puzzle for that slot.
@available(iOS 26.0, *)
struct OpenCheckInIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open Check-in"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @Parameter(title: "Day") var dayKey: String
    @Parameter(title: "Slot") var slotIndex: Int

    init() {}

    init(key: SlotKey) {
        dayKey = key.dayKey
        slotIndex = key.slotIndex
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let key = SlotKey(dayKey: dayKey, slotIndex: slotIndex)
        try? AlarmManager.shared.stop(id: AlarmService.alarmID(for: key))
        AppRouter.shared.requestedSlot = key
        return .result()
    }
}
