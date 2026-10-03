import XCTest
@testable import StillAlive

final class PlanLimitsTests: XCTestCase {
    func partner(_ status: String, incoming: Bool = false) -> Partnership {
        Partnership(partnerID: UUID().uuidString, partnerName: "P", status: status, isIncoming: incoming)
    }

    func testAcceptedAndSentInvitesCountTowardThePartnerLimit() {
        let two = [partner("accepted"), partner("pending")]
        XCTAssertEqual(PlanLimits.partnerSlotsUsed(two), 2)
        XCTAssertTrue(PlanLimits.canAddPartner(two))

        let full = two + [partner("accepted")]
        XCTAssertFalse(PlanLimits.canAddPartner(full))
    }

    func testIncomingRequestsAndDeclinedDoNotCount() {
        let list = [partner("accepted"), partner("accepted"), partner("pending", incoming: true), partner("declined")]
        XCTAssertEqual(PlanLimits.partnerSlotsUsed(list), 2)
        XCTAssertTrue(PlanLimits.canAddPartner(list))
    }

    func testSharedLimitsAreThree() {
        XCTAssertEqual(PlanLimits.partners, 3)
        XCTAssertEqual(EmergencyContact.maxCount, 3)
        XCTAssertEqual(PlanLimits.checkInTimes, 3)
    }
}
