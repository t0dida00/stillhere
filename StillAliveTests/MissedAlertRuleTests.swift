import XCTest
@testable import StillAlive

final class MissedAlertRuleTests: XCTestCase {
    func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

    func slot(_ scheduled: String, _ state: SlotState, resolved: String? = nil) -> RemoteSlot {
        RemoteSlot(ownerID: "P", dayKey: String(scheduled.prefix(10)), slotIndex: scheduled.contains("T21") ? 1 : 0,
                   scheduledAt: date(scheduled), state: state, resolvedAt: resolved.map(date))
    }

    func testEveryNewMissIsReportedOldestFirst() {
        let slots = [
            slot("2026-10-02T09:00:00Z", .missed, resolved: "2026-10-02T10:00:00Z"),
            slot("2026-10-01T21:00:00Z", .missed, resolved: "2026-10-01T22:00:00Z"),
            slot("2026-10-01T09:00:00Z", .checkedIn, resolved: "2026-10-01T09:10:00Z"),
        ]
        let misses = MissedAlertRule.newMisses(slots, since: date("2026-10-01T12:00:00Z"), now: date("2026-10-02T12:00:00Z"))
        XCTAssertEqual(misses.map(\.dayKey), ["2026-10-01", "2026-10-02"])
    }

    func testMissesBeforeLastCheckOrAfterNowAreSkipped() {
        let slots = [
            slot("2026-10-01T09:00:00Z", .missed, resolved: "2026-10-01T10:00:00Z"),
            slot("2026-10-01T21:00:00Z", .missed, resolved: "2026-10-01T22:00:00Z"),
        ]
        // Already checked up to 10:00 (inclusive), and "now" is before the 21:00 slot's deadline.
        XCTAssertTrue(MissedAlertRule.newMisses(slots, since: date("2026-10-01T10:00:00Z"), now: date("2026-10-01T21:30:00Z")).isEmpty)
    }

    func testSkipsAndPendingAreNotMisses() {
        let slots = [slot("2026-10-01T09:00:00Z", .skipped, resolved: "2026-10-01T09:05:00Z"), slot("2026-10-01T21:00:00Z", .pending)]
        XCTAssertTrue(MissedAlertRule.newMisses(slots, since: .distantPast, now: date("2026-10-02T00:00:00Z")).isEmpty)
    }
}

final class MockScenarioTests: XCTestCase {
    @MainActor
    func testParsesMockPartnerArgument() {
        XCTAssertEqual(MockScenario.parse("Dad@04:28/1")?.minutes, 268)
        XCTAssertEqual(MockScenario.parse("Dad@04:28/1")?.grace, 1)
        XCTAssertEqual(MockScenario.parse("Mom@21:00")?.grace, 60)
        XCTAssertNil(MockScenario.parse("Dad@25:00"))
        XCTAssertNil(MockScenario.parse("Dad"))
    }

    func testTestPartnerMissesFromStartPoint() {
        let utc = TimeZone(identifier: "UTC")!
        let date = { ISO8601DateFormatter().date(from: $0)! }
        let slots = MockSyncService.history(for: "DAD00001", now: date("2026-10-04T04:30:00Z"), timeZone: utc, days: 1,
                                            slotTimes: [268], graceMinutes: 1, missesFrom: date("2026-10-04T00:00:00Z"))
        XCTAssertEqual(slots.map(\.state), [.missed])
        XCTAssertEqual(slots.first?.resolvedAt, date("2026-10-04T04:29:00Z"))
    }
}

final class RequestCheckInRuleTests: XCTestCase {
    func snapshot(_ hour: Int, _ state: SlotState) -> SlotSnapshot {
        SlotSnapshot(key: SlotKey(dayKey: "2026-10-04", slotIndex: hour),
                     scheduledAt: Date(timeIntervalSince1970: TimeInterval(hour * 3600)), state: state)
    }

    func testMissingNowUsesTheLatestDecidedCheckIn() {
        XCTAssertTrue(MissedAlertRule.isMissingNow([snapshot(9, .checkedIn), snapshot(21, .missed)]))
        // A later pending check-in doesn't clear the miss.
        XCTAssertTrue(MissedAlertRule.isMissingNow([snapshot(9, .missed), snapshot(21, .pending)]))
        XCTAssertFalse(MissedAlertRule.isMissingNow([snapshot(9, .missed), snapshot(21, .checkedIn)]))
        XCTAssertFalse(MissedAlertRule.isMissingNow([snapshot(9, .missed), snapshot(21, .skipped)]))
        XCTAssertFalse(MissedAlertRule.isMissingNow([]))
    }

    func testRequestCooldown() {
        let sent = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(MissedAlertRule.canRequestCheckIn(lastRequestAt: nil, now: sent))
        XCTAssertFalse(MissedAlertRule.canRequestCheckIn(lastRequestAt: sent, now: sent.addingTimeInterval(60)))
        XCTAssertTrue(MissedAlertRule.canRequestCheckIn(lastRequestAt: sent, now: sent.addingTimeInterval(5 * 60)))
    }
}
