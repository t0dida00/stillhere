import XCTest
@testable import StillAlive

final class MetricsCalculatorTests: XCTestCase {
    func slot(_ day: String, _ index: Int, _ state: SlotState) -> SlotSnapshot {
        SlotSnapshot(key: SlotKey(dayKey: day, slotIndex: index), scheduledAt: .now, state: state)
    }

    func testStreakIgnoresTodayInProgress() {
        let slots = [
            slot("2026-09-29", 0, .checkedIn), slot("2026-09-29", 1, .checkedIn),
            slot("2026-09-30", 0, .checkedIn), slot("2026-09-30", 1, .checkedIn),
            slot("2026-10-01", 0, .checkedIn), slot("2026-10-01", 1, .pending),
        ]
        XCTAssertEqual(MetricsCalculator.compute(slots, todayKey: "2026-10-01"),
                       Metrics(checkedInDays: 2, currentStreak: 2, missedCount: 0))
    }

    func testCompletedTodayCountsAndMissBreaksStreak() {
        let slots = [
            slot("2026-09-29", 0, .checkedIn),
            slot("2026-09-30", 0, .missed),
            slot("2026-10-01", 0, .checkedIn),
        ]
        XCTAssertEqual(MetricsCalculator.compute(slots, todayKey: "2026-10-01"),
                       Metrics(checkedInDays: 2, currentStreak: 1, missedCount: 1))
    }

    func testSkipCountsAsDoneAndKeepsStreak() {
        let slots = [
            slot("2026-09-30", 0, .checkedIn), slot("2026-09-30", 1, .skipped),
            slot("2026-10-01", 0, .skipped), slot("2026-10-01", 1, .pending),
        ]
        XCTAssertEqual(MetricsCalculator.compute(slots, todayKey: "2026-10-01"),
                       Metrics(checkedInDays: 1, currentStreak: 1, missedCount: 0))
    }

    func testMissTodayResetsStreak() {
        let slots = [slot("2026-09-30", 0, .checkedIn), slot("2026-10-01", 0, .missed), slot("2026-10-01", 1, .pending)]
        XCTAssertEqual(MetricsCalculator.compute(slots, todayKey: "2026-10-01").currentStreak, 0)
    }

    func testGapBreaksStreak() {
        let slots = [slot("2026-09-28", 0, .checkedIn), slot("2026-09-30", 0, .checkedIn)]
        XCTAssertEqual(MetricsCalculator.compute(slots, todayKey: "2026-10-01").currentStreak, 1)
    }

    func testEmpty() {
        XCTAssertEqual(MetricsCalculator.compute([], todayKey: "2026-10-01"), Metrics(checkedInDays: 0, currentStreak: 0, missedCount: 0))
    }
}
