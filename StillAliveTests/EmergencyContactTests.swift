import XCTest
@testable import StillAlive

final class EmergencyContactTests: XCTestCase {
    func testLinksOpenTheRightApp() {
        XCTAssertEqual(EmergencyContact(kind: .phone, value: "+84 912 345 678").url?.absoluteString, "tel:+84912345678")
        XCTAssertEqual(EmergencyContact(kind: .zalo, value: "0912 345 678").url?.absoluteString, "https://zalo.me/0912345678")
        XCTAssertEqual(EmergencyContact(kind: .whatsApp, value: "+84 912-345-678").url?.absoluteString, "https://wa.me/84912345678")
        XCTAssertEqual(EmergencyContact(kind: .telegram, value: "@linh_ng").url?.absoluteString, "https://t.me/linh_ng")
        XCTAssertEqual(EmergencyContact(kind: .telegram, value: "+84 912 345 678").url?.absoluteString, "https://t.me/+84912345678")
        XCTAssertNil(EmergencyContact(kind: .phone, value: "  ").url)
    }

    func testUserKeepsAtMostTheContactLimit() {
        let user = LocalUser(id: "ME000001", displayName: "Me")
        XCTAssertEqual(user.emergencyContacts, [])
        user.emergencyContacts = (1...4).map { EmergencyContact(kind: .phone, value: "09\($0)") }
        XCTAssertEqual(user.emergencyContacts.map(\.value), Array(["091", "092", "093", "094"].prefix(EmergencyContact.maxCount)))
    }
}

final class MockPartnerContactsTests: XCTestCase {
    func testMockContactsAreStableAndWithinTheLimit() {
        for code in ["DAD00001", "MOM00002", "NBA6EKJ3", "6TMMZ3KQ"] {
            let first = MockSyncService.emergencyContacts(for: code)
            XCTAssertLessThanOrEqual(first.count, PlanLimits.emergencyContacts)
            XCTAssertEqual(first.map(\.value), MockSyncService.emergencyContacts(for: code).map(\.value))
            XCTAssertTrue(first.allSatisfy { $0.url != nil })
        }
    }
}
