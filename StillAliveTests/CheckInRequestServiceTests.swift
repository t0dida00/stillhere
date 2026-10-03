import SwiftData
import XCTest
@testable import StillAlive

private final class RequestSync: SyncService {
    var inbox: [IncomingCheckInRequest]
    var answered: [String] = []
    init(inbox: [IncomingCheckInRequest]) { self.inbox = inbox }
    func push(_ slots: [CheckInSlot]) async throws {}
    func pull(partnerID: String) async throws -> [RemoteSlot] { [] }
    func sendInvite(to partnerID: String) async throws {}
    func respond(to partnerID: String, accept: Bool) async throws {}
    func partnerSharesLocation(_ partnerID: String) async throws -> Bool { false }
    func emergencyContacts(of partnerID: String) async throws -> [EmergencyContact] { [] }
    func requestCheckIn(from partnerID: String) async throws {}
    func incomingCheckInRequests() async throws -> [IncomingCheckInRequest] { inbox }
    func answerCheckInRequest(_ id: String) async throws { answered.append(id) }
}

@MainActor
final class CheckInRequestServiceTests: XCTestCase {
    var context: ModelContext!
    var container: ModelContainer!

    override func setUp() async throws {
        container = try ModelContainer(for: LocalUser.self, CheckInSlot.self, Partnership.self, AppSettings.self, AlertRecord.self,
                                       CheckInRequest.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
        let dad = Partnership(partnerID: "DAD00001", partnerName: "Demo partner", status: "accepted")
        dad.nickname = "Dad"
        context.insert(dad)
    }

    func testNewRequestsFromPartnersAreSavedOnceAndOpen() async {
        let sync = RequestSync(inbox: [
            IncomingCheckInRequest(id: "r1", partnerID: "DAD00001", requestedAt: .now),
            IncomingCheckInRequest(id: "r2", partnerID: "STRANGER", requestedAt: .now),
        ])
        let service = CheckInRequestService(context: context, sync: sync)
        await service.fetchNew()
        await service.fetchNew()

        let saved = (try? context.fetch(FetchDescriptor<CheckInRequest>())) ?? []
        XCTAssertEqual(saved.map(\.id), ["r1"])
        XCTAssertEqual(saved.first?.partnerName, "Dad")
        XCTAssertEqual(service.oldestOpen()?.id, "r1")
    }

    func testAnsweringOrDismissingClosesTheRequest() async {
        let sync = RequestSync(inbox: [IncomingCheckInRequest(id: "r1", partnerID: "DAD00001", requestedAt: .now)])
        let service = CheckInRequestService(context: context, sync: sync)
        await service.fetchNew()
        service.dismiss(id: "r1")
        XCTAssertNil(service.oldestOpen())

        sync.inbox = [IncomingCheckInRequest(id: "r2", partnerID: "DAD00001", requestedAt: .now)]
        await service.fetchNew()
        service.answerAll()
        XCTAssertNil(service.oldestOpen())
        XCTAssertNotNil(service.request(id: "r2")?.answeredAt)
    }
}
