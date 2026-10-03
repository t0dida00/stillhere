import XCTest
@testable import StillAlive

final class NotificationPlannerTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!

    func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    func testRemindersRepeatUntilGraceEnds() {
        let plan = NotificationPlanner.plan(now: date("2026-10-01T00:00:00Z"), days: 1, slotTimes: [540], timeZone: utc,
                                            graceMinutes: 60, remindEveryMinutes: 10, resolved: [])
        XCTAssertEqual(plan.map(\.sequence), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(plan.first?.fireDate, date("2026-10-01T09:00:00Z"))
        XCTAssertEqual(plan.last?.fireDate, date("2026-10-01T09:50:00Z"))
    }

    func testSkipsPastAndResolved() {
        let now = date("2026-10-01T09:25:00Z")
        let plan = NotificationPlanner.plan(now: now, days: 2, slotTimes: [540, 1260], timeZone: utc,
                                            graceMinutes: 60, remindEveryMinutes: 10,
                                            resolved: [SlotKey(dayKey: "2026-10-01", slotIndex: 1)])
        XCTAssertTrue(plan.allSatisfy { $0.fireDate > now })
        XCTAssertFalse(plan.contains { $0.key == SlotKey(dayKey: "2026-10-01", slotIndex: 1) })
        // Today's 09:00 slot still gets 09:30, 09:40, 09:50.
        XCTAssertEqual(plan.filter { $0.key == SlotKey(dayKey: "2026-10-01", slotIndex: 0) }.count, 3)
    }

    func testCappedAtLimitAndSorted() {
        let plan = NotificationPlanner.plan(now: date("2026-10-01T00:00:00Z"), slotTimes: [540, 1260], timeZone: utc,
                                            graceMinutes: 60, remindEveryMinutes: 10, resolved: [])
        XCTAssertEqual(plan.count, NotificationPlanner.maxPending)
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
        XCTAssertEqual(Set(plan.map(\.identifier)).count, plan.count)
    }

    func testUpcomingSlotsSkipStartedAndResolved() {
        let now = date("2026-10-01T09:25:00Z")
        let slots = NotificationPlanner.upcomingSlots(now: now, days: 2, slotTimes: [540, 1260], timeZone: utc,
                                                     resolved: [SlotKey(dayKey: "2026-10-02", slotIndex: 0)])
        // Today's 09:00 has started; tomorrow's 09:00 is resolved.
        XCTAssertEqual(slots.map(\.key), [SlotKey(dayKey: "2026-10-01", slotIndex: 1), SlotKey(dayKey: "2026-10-02", slotIndex: 1)])
    }

    func testStoredTodayReplacesSettingsForToday() {
        let now = date("2026-10-01T09:25:00Z")
        let today = [SlotSpec(key: SlotKey(dayKey: "2026-10-01", slotIndex: 2), scheduledAt: date("2026-10-01T10:00:00Z"))]
        let slots = NotificationPlanner.upcomingSlots(now: now, days: 2, slotTimes: [540, 1260], timeZone: utc, resolved: [], today: today)
        XCTAssertEqual(slots.map(\.key), [SlotKey(dayKey: "2026-10-01", slotIndex: 2),
                                          SlotKey(dayKey: "2026-10-02", slotIndex: 0), SlotKey(dayKey: "2026-10-02", slotIndex: 1)])
    }

    @available(iOS 26.0, *)
    func testAlarmIDIsStablePerSlot() {
        let key = SlotKey(dayKey: "2026-10-01", slotIndex: 0)
        XCTAssertEqual(AlarmService.alarmID(for: key), AlarmService.alarmID(for: key))
        XCTAssertNotEqual(AlarmService.alarmID(for: key), AlarmService.alarmID(for: SlotKey(dayKey: "2026-10-01", slotIndex: 1)))
    }
}
