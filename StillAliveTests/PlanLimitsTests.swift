import XCTest
@testable import StillAlive

final class PlanLimitsTests: XCTestCase {
    func partner(_ status: String, incoming: Bool = false) -> Partnership {
        Partnership(partnerID: UUID().uuidString, partnerName: "P", status: status, isIncoming: incoming)
    }

    func testFreePlanLimits() {
        XCTAssertEqual(PlanLimits.partners, 1)
        XCTAssertEqual(EmergencyContact.maxCount, 3)
        XCTAssertEqual(PlanLimits.checkInTimes, 3)
    }

    func testAcceptedPartnersAndSentInvitesFillTheLimit() {
        XCTAssertTrue(PlanLimits.canAddPartner([]))
        XCTAssertFalse(PlanLimits.canAddPartner([partner("accepted")]))
        // A sent invite takes the place of the partner it may become.
        XCTAssertFalse(PlanLimits.canAddPartner([partner("pending")]))
    }

    func testIncomingRequestsAndDeclinedDoNotCount() {
        let list = [partner("pending", incoming: true), partner("declined")]
        XCTAssertEqual(PlanLimits.partnerSlotsUsed(list), 0)
        XCTAssertTrue(PlanLimits.canAddPartner(list))
    }
}
