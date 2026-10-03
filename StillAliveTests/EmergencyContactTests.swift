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

    func testUserKeepsAtMostThreeContacts() {
        let user = LocalUser(id: "ME000001", displayName: "Me")
        XCTAssertEqual(user.emergencyContacts, [])
        user.emergencyContacts = (1...4).map { EmergencyContact(kind: .phone, value: "09\($0)") }
        XCTAssertEqual(user.emergencyContacts.map(\.value), ["091", "092", "093"])
    }
}
