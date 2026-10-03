import SwiftData
import XCTest
@testable import StillAlive

private struct OneMissSync: SyncService {
    let missedAt: Date
    func push(_ slots: [CheckInSlot]) async throws {}
    func pull(partnerID: String) async throws -> [RemoteSlot] {
        [RemoteSlot(ownerID: partnerID, dayKey: "2026-10-04", slotIndex: 0, scheduledAt: missedAt.addingTimeInterval(-60),
                    state: .missed, resolvedAt: missedAt)]
    }
    func sendInvite(to partnerID: String) async throws {}
    func respond(to partnerID: String, accept: Bool) async throws {}
    func partnerSharesLocation(_ partnerID: String) async throws -> Bool { false }
}

@MainActor
final class PartnerAlertServiceTests: XCTestCase {
    func testEachMissIsSavedOnceForTheNotificationsTab() async throws {
        let container = try ModelContainer(for: LocalUser.self, CheckInSlot.self, Partnership.self, AppSettings.self, AlertRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let date = { ISO8601DateFormatter().date(from: $0)! }
        context.insert(LocalUser(id: "ME000001", displayName: "Me", timeZoneID: "UTC"))
        let partner = Partnership(partnerID: "DAD00001", partnerName: "Dad", status: "accepted")
        partner.lastMissCheckAt = date("2026-10-04T04:00:00Z")
        context.insert(partner)

        let service = PartnerAlertService(context: context, sync: OneMissSync(missedAt: date("2026-10-04T04:29:00Z")))
        await service.checkForMisses(now: date("2026-10-04T04:32:00Z"))
        // Pretend the marker was reset; the same miss must not be saved twice.
        partner.lastMissCheckAt = date("2026-10-04T04:00:00Z")
        await service.checkForMisses(now: date("2026-10-04T04:37:00Z"))

        let alerts = try context.fetch(FetchDescriptor<AlertRecord>())
        XCTAssertEqual(alerts.map(\.partnerName), ["Dad"])
        XCTAssertEqual(alerts.first?.isRead, false)
        XCTAssertEqual(alerts.first?.id, "partner-miss.DAD00001.2026-10-04#0")
    }
}
