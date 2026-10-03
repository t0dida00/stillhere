import XCTest
@testable import StillAlive

final class IdentityServiceTests: XCTestCase {
    func testPublicIDFormat() throws {
        let allowed = Set(IdentityService.alphabet)
        for _ in 0..<100 {
            let id = try IdentityService.generatePublicID()
            XCTAssertEqual(id.count, 8)
            XCTAssertTrue(id.allSatisfy(allowed.contains))
        }
    }

    func testNormalizeCode() {
        XCTAssertEqual(IdentityService.normalizeCode("abcd-1234"), "ABCD1234")
        XCTAssertEqual(IdentityService.normalizeCode(" 0o1il u "), "00111")
        XCTAssertEqual(IdentityService.normalizeCode("ABCD1234EXTRA"), "ABCD1234")
    }

    func testCodeFromScannedInvite() {
        XCTAssertEqual(IdentityService.inviteURL(for: "ABCD1234").absoluteString, "stillhere://invite/ABCD1234")
        XCTAssertEqual(IdentityService.code(fromScanned: "stillhere://invite/ABCD1234"), "ABCD1234")
        XCTAssertEqual(IdentityService.code(fromScanned: "StillHere://Invite/abcd-1234"), "ABCD1234")
        // Links and QR codes from before the rename.
        XCTAssertEqual(IdentityService.code(fromScanned: "stillalive://invite/ABCD1234"), "ABCD1234")
        XCTAssertEqual(IdentityService.code(fromScanned: "StillAlive://Invite/abcd-1234"), "ABCD1234")
        XCTAssertEqual(IdentityService.code(fromScanned: " abcd 1234 "), "ABCD1234")
        XCTAssertNil(IdentityService.code(fromScanned: "https://example.com/ABCD1234"))
        XCTAssertNil(IdentityService.code(fromScanned: "stillalive://other/ABCD1234"))
        XCTAssertNil(IdentityService.code(fromScanned: "Meet me at ABCD1234 tomorrow"))
        XCTAssertNil(IdentityService.code(fromScanned: "ABC123"))
    }

    func testIsValidCode() {
        XCTAssertTrue(IdentityService.isValidCode("ABCD1234"))
        XCTAssertFalse(IdentityService.isValidCode("ABCD123"))
        XCTAssertFalse(IdentityService.isValidCode("ABCD123U"))
    }

    func testMockPartnerHistoryIsStableAndPlausible() {
        let utc = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-10-01T09:30:00Z")!
        let first = MockSyncService.history(for: "PARTNER1", now: now, timeZone: utc, days: 10)
        XCTAssertEqual(first, MockSyncService.history(for: "PARTNER1", now: now, timeZone: utc, days: 10))
        XCTAssertNotEqual(first.map(\.state), MockSyncService.history(for: "PARTNER2", now: now, timeZone: utc, days: 10).map(\.state))
        XCTAssertEqual(first.count, 20)
        // Nothing in the future is resolved, and nothing past its grace window is pending.
        XCTAssertTrue(first.filter { $0.scheduledAt > now }.allSatisfy { $0.state == .pending })
        XCTAssertTrue(first.filter { $0.scheduledAt.addingTimeInterval(3600) <= now }.allSatisfy { $0.state != .pending })
        XCTAssertTrue(first.compactMap(\.resolvedAt).allSatisfy { $0 <= now })
        XCTAssertTrue(MockSyncService.history(for: "PARTNER1", now: now, timeZone: utc, days: 10, sharesLocation: false)
            .allSatisfy { $0.latitude == nil && $0.longitude == nil })
        XCTAssertTrue(MockSyncService.sharesLocation("C5G9V694"))
        XCTAssertFalse(MockSyncService.sharesLocation("8JKYFB2E"))
        // Only check-ins carry a location.
        XCTAssertTrue(first.allSatisfy { ($0.latitude != nil) == ($0.state == .checkedIn) })
    }
}
