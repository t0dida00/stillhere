import SwiftData
import XCTest
@testable import StillAlive

@MainActor
final class SlotResolverTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var user: LocalUser!
    var settings: AppSettings!

    func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    override func setUp() async throws {
        container = try ModelContainer(
            for: LocalUser.self, CheckInSlot.self, Partnership.self, AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        user = LocalUser(id: "TEST0001", displayName: "Test", timeZoneID: "UTC", createdAt: date("2026-09-29T08:00:00Z"))
        // Two times a day, independent of the free-plan default.
        settings = AppSettings(slotTimes: [540, 1260])
        context.insert(user)
        context.insert(settings)
    }

    func testCreatesSlotsSinceCreationAndMarksMissed() {
        let slots = SlotResolver(context: context).reconcile(user: user, settings: settings, now: date("2026-10-01T09:30:00Z"))
        // 3 days × 2 slots.
        XCTAssertEqual(slots.count, 6)
        let today = slots.filter { $0.dayKey == "2026-10-01" }
        XCTAssertEqual(today.map(\.state), [.pending, .pending])
        XCTAssertTrue(slots.filter { $0.dayKey != "2026-10-01" }.allSatisfy { $0.state == .missed && $0.resolvedAt != nil })
    }

    func testSkipsSlotsClosedBeforeCreation() {
        user.createdAt = date("2026-10-01T12:00:00Z")
        let slots = SlotResolver(context: context).reconcile(user: user, settings: settings, now: date("2026-10-01T12:00:00Z"))
        XCTAssertEqual(slots.map(\.slotIndex), [1])
    }

    func testReconcileIsIdempotentAndKeepsResolvedState() {
        let resolver = SlotResolver(context: context)
        let now = date("2026-10-01T09:30:00Z")
        let first = resolver.reconcile(user: user, settings: settings, now: now)
        first.first { $0.dayKey == "2026-10-01" && $0.slotIndex == 0 }?.state = .checkedIn
        let second = resolver.reconcile(user: user, settings: settings, now: now)
        XCTAssertEqual(second.count, first.count)
        XCTAssertEqual(second.first { $0.dayKey == "2026-10-01" && $0.slotIndex == 0 }?.state, .checkedIn)
    }

    func testSettingsChangeMovesPendingSlotsToday() {
        let resolver = SlotResolver(context: context)
        resolver.reconcile(user: user, settings: settings, now: date("2026-10-01T07:00:00Z"))
        settings.slotTimes = [600]
        let today = resolver.reconcile(user: user, settings: settings, now: date("2026-10-01T07:00:00Z"))
            .filter { $0.dayKey == "2026-10-01" }
        XCTAssertEqual(today.map(\.scheduledAt), [date("2026-10-01T10:00:00Z")])
    }

    func testResolvedTodayIgnoresEarlierNewTimes() {
        let resolver = SlotResolver(context: context)
        let now = date("2026-10-01T09:30:00Z")
        resolver.reconcile(user: user, settings: settings, now: now)
            .first { $0.dayKey == "2026-10-01" && $0.slotIndex == 0 }?.state = .checkedIn
        settings.slotTimes = [360, 540, 1260]
        let today = resolver.reconcile(user: user, settings: settings, now: now).filter { $0.dayKey == "2026-10-01" }
        XCTAssertEqual(today.map(\.scheduledAt), [date("2026-10-01T09:00:00Z"), date("2026-10-01T21:00:00Z")])
        XCTAssertEqual(today.map(\.state), [.checkedIn, .pending])
    }

    func testResolvedTodayAppliesLaterNewTimesWithFreshIndexes() {
        let resolver = SlotResolver(context: context)
        let now = date("2026-10-01T09:30:00Z")
        resolver.reconcile(user: user, settings: settings, now: now)
            .first { $0.dayKey == "2026-10-01" && $0.slotIndex == 0 }?.state = .checkedIn
        // 09:00 moves to 10:00 after it was checked in; 21:00 stays.
        settings.slotTimes = [600, 1260]
        let today = resolver.reconcile(user: user, settings: settings, now: now).filter { $0.dayKey == "2026-10-01" }
        XCTAssertEqual(today.map(\.key), [SlotKey(dayKey: "2026-10-01", slotIndex: 0), SlotKey(dayKey: "2026-10-01", slotIndex: 1),
                                          SlotKey(dayKey: "2026-10-01", slotIndex: 2)])
        XCTAssertEqual(today.map(\.scheduledAt), [date("2026-10-01T09:00:00Z"), date("2026-10-01T10:00:00Z"), date("2026-10-01T21:00:00Z")])
        XCTAssertEqual(today.map(\.state), [.checkedIn, .pending, .pending])
    }

    func testReconciledPastDayIsNotRefilled() {
        let resolver = SlotResolver(context: context)
        resolver.reconcile(user: user, settings: settings, now: date("2026-09-30T12:00:00Z"))
        settings.slotTimes = [360, 540, 1260]
        let pastDay = resolver.reconcile(user: user, settings: settings, now: date("2026-10-01T07:00:00Z"))
            .filter { $0.dayKey == "2026-09-30" }
        XCTAssertEqual(pastDay.count, 2)
    }
}
