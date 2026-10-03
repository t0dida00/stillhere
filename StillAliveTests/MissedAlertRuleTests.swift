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
