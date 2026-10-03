import XCTest
@testable import StillAlive

final class SlotScheduleTests: XCTestCase {
    let saigon = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    let newYork = TimeZone(identifier: "America/New_York")!

    func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    func testDayKeyUsesUserTimeZone() {
        // 20:00 UTC on Sep 30 is already Oct 1 in Saigon (UTC+7).
        let instant = date("2026-09-30T20:00:00Z")
        XCTAssertEqual(DayKey.string(for: instant, in: saigon), "2026-10-01")
        XCTAssertEqual(DayKey.string(for: instant, in: newYork), "2026-09-30")
    }

    func testDayKeyDisplay() {
        XCTAssertEqual(DayKey.display("2026-10-02"), "02/10/2026")
        XCTAssertEqual(DayKey.display("bad"), "bad")
    }

    func testDayKeyArithmetic() {
        XCTAssertEqual(DayKey.adding(-1, to: "2026-03-01"), "2026-02-28")
        XCTAssertEqual(DayKey.adding(1, to: "2026-12-31"), "2027-01-01")
    }

    func testSpecsForOneDay() {
        let specs = SlotPlanner.specs(forDayContaining: date("2026-10-01T05:00:00Z"), slotTimes: [1260, 540], timeZone: saigon)
        XCTAssertEqual(specs.map(\.key), [SlotKey(dayKey: "2026-10-01", slotIndex: 0), SlotKey(dayKey: "2026-10-01", slotIndex: 1)])
        // 09:00 and 21:00 in UTC+7.
        XCTAssertEqual(specs.map(\.scheduledAt), [date("2026-10-01T02:00:00Z"), date("2026-10-01T14:00:00Z")])
    }

    func testSpecsAcrossDays() {
        let specs = SlotPlanner.specs(from: date("2026-10-01T00:00:00Z"), through: date("2026-10-03T12:00:00Z"), slotTimes: [540, 1260], timeZone: saigon)
        XCTAssertEqual(specs.count, 6)
        XCTAssertEqual(Set(specs.map(\.key.dayKey)), ["2026-10-01", "2026-10-02", "2026-10-03"])
    }

    func testSpecsOnDSTDay() {
        // US clocks spring forward on 2026-03-08; 09:00 local is 13:00 UTC that day.
        let specs = SlotPlanner.specs(forDayContaining: date("2026-03-08T15:00:00Z"), slotTimes: [540], timeZone: newYork)
        XCTAssertEqual(specs.first?.scheduledAt, date("2026-03-08T13:00:00Z"))
    }

    func testNormalizedSortsDedupesAndDropsInvalid() {
        XCTAssertEqual(SlotPlanner.normalized([1260, 540, 540, -5, 1440]), [540, 1260])
    }

    func testRules() {
        let slot = SlotSnapshot(key: SlotKey(dayKey: "2026-10-01", slotIndex: 0), scheduledAt: date("2026-10-01T09:00:00Z"), state: .pending)
        XCTAssertFalse(SlotRules.isOpen(slot, now: date("2026-10-01T08:59:00Z"), graceMinutes: 60))
        XCTAssertTrue(SlotRules.isOpen(slot, now: date("2026-10-01T09:00:00Z"), graceMinutes: 60))
        XCTAssertTrue(SlotRules.isOpen(slot, now: date("2026-10-01T09:59:00Z"), graceMinutes: 60))
        XCTAssertFalse(SlotRules.isOpen(slot, now: date("2026-10-01T10:00:00Z"), graceMinutes: 60))

        XCTAssertEqual(SlotRules.resolvedState(slot, now: date("2026-10-01T09:59:00Z"), graceMinutes: 60), .pending)
        XCTAssertEqual(SlotRules.resolvedState(slot, now: date("2026-10-01T10:00:00Z"), graceMinutes: 60), .missed)

        var skipped = slot
        skipped.state = .skipped
        XCTAssertEqual(SlotRules.resolvedState(skipped, now: date("2026-10-02T00:00:00Z"), graceMinutes: 60), .skipped)
        XCTAssertFalse(SlotRules.isOpen(skipped, now: date("2026-10-01T09:30:00Z"), graceMinutes: 60))
    }
}
