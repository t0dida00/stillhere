import XCTest
@testable import StillAlive

final class MissedAlertRuleTests: XCTestCase {
    func slot(_ time: String, _ state: SlotState) -> SlotSnapshot {
        let date = ISO8601DateFormatter().date(from: time)!
        return SlotSnapshot(key: SlotKey(dayKey: String(time.prefix(10)), slotIndex: 0), scheduledAt: date, state: state)
    }

    func testOneMissDoesNotAlert() {
        let run = MissedAlertRule.consecutiveMisses([slot("2026-10-01T09:00:00Z", .checkedIn), slot("2026-10-01T21:00:00Z", .missed)])
        XCTAssertEqual(run, 1)
        XCTAssertNil(MissedAlertRule.alert(run: run, alreadyAlerted: 0))
    }

    func testTwoMissesInARowAlert() {
        let run = MissedAlertRule.consecutiveMisses([slot("2026-10-01T09:00:00Z", .missed), slot("2026-10-01T21:00:00Z", .missed)])
        XCTAssertEqual(MissedAlertRule.alert(run: run, alreadyAlerted: 0), .missedInARow(2))
    }

    func testSkipBreaksTheRun() {
        let run = MissedAlertRule.consecutiveMisses([
            slot("2026-10-01T09:00:00Z", .missed), slot("2026-10-01T13:00:00Z", .skipped), slot("2026-10-01T21:00:00Z", .missed),
        ])
        XCTAssertEqual(run, 1)
        XCTAssertNil(MissedAlertRule.alert(run: run, alreadyAlerted: 0))
    }

    func testRunCountsAcrossMidnightAndIgnoresPending() {
        // 21:00 missed, next day 09:00 missed, 21:00 still pending; given out of order.
        let run = MissedAlertRule.consecutiveMisses([
            slot("2026-10-02T21:00:00Z", .pending), slot("2026-10-02T09:00:00Z", .missed), slot("2026-10-01T21:00:00Z", .missed),
            slot("2026-10-01T09:00:00Z", .checkedIn),
        ])
        XCTAssertEqual(run, 2)
        XCTAssertEqual(MissedAlertRule.alert(run: run, alreadyAlerted: 0), .missedInARow(2))
    }

    func testFollowUpOncePerExtraMissThenAllGood() {
        XCTAssertNil(MissedAlertRule.alert(run: 2, alreadyAlerted: 2))
        XCTAssertEqual(MissedAlertRule.alert(run: 3, alreadyAlerted: 2), .stillMissing(3))
        XCTAssertNil(MissedAlertRule.alert(run: 3, alreadyAlerted: 3))
        XCTAssertEqual(MissedAlertRule.alert(run: 0, alreadyAlerted: 3), .allGood)
        XCTAssertNil(MissedAlertRule.alert(run: 0, alreadyAlerted: 0))
    }
}
