import SwiftData
import XCTest
@testable import StillAlive

@MainActor
final class AccountStoreTests: XCTestCase {
    var defaults: UserDefaults!
    var opened: [String] = []

    override func setUp() {
        defaults = UserDefaults(suiteName: "AccountStoreTests")
        defaults.removePersistentDomain(forName: "AccountStoreTests")
        opened = []
    }

    func makeStore() -> AccountStore {
        AccountStore(defaults: defaults) { key in
            self.opened.append(key)
            return try! ModelContainer(for: Schema(AccountStore.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }

    func testStartsWithDefaultAccountLoggedIn() {
        let store = makeStore()
        XCTAssertEqual(store.current, AccountStore.defaultKey)
        XCTAssertFalse(store.isLoggedOut)
        XCTAssertEqual(opened, [AccountStore.defaultKey])
        XCTAssertTrue(store.loginOptions.isEmpty)
    }

    func testCreateLogOutAndLogInSwitchesStores() {
        let store = makeStore()
        store.record(publicID: "AAAA0001", displayName: "Khoa")
        store.logOut()
        XCTAssertTrue(store.isLoggedOut)

        store.createAccount()
        let newKey = store.current
        XCTAssertNotEqual(newKey, AccountStore.defaultKey)
        XCTAssertFalse(store.isLoggedOut)
        XCTAssertEqual(opened.last, newKey)
        XCTAssertTrue(store.canCancelNewAccount)

        store.record(publicID: "BBBB0002", displayName: "Mai")
        XCTAssertFalse(store.canCancelNewAccount)
        store.logOut()
        XCTAssertEqual(store.loginOptions.map(\.displayName), ["Khoa", "Mai"])

        store.logIn(store.loginOptions[0])
        XCTAssertEqual(store.current, AccountStore.defaultKey)
        XCTAssertFalse(store.isLoggedOut)
    }

    func testCancelNewAccountReturnsToLogIn() {
        let store = makeStore()
        store.record(publicID: "AAAA0001", displayName: "Khoa")
        store.logOut()
        store.createAccount()
        store.cancelNewAccount()
        XCTAssertTrue(store.isLoggedOut)
        XCTAssertEqual(store.current, AccountStore.defaultKey)
        XCTAssertEqual(store.accounts.count, 1)
    }

    func testFirstAccountCannotCancelOnboarding() {
        XCTAssertFalse(makeStore().canCancelNewAccount)
    }

    func testStateSurvivesRelaunch() {
        let store = makeStore()
        store.record(publicID: "AAAA0001", displayName: "Khoa")
        store.createAccount()
        store.record(publicID: "BBBB0002", displayName: "Mai")
        store.logOut()

        let relaunched = makeStore()
        XCTAssertEqual(relaunched.current, store.current)
        XCTAssertTrue(relaunched.isLoggedOut)
        XCTAssertEqual(relaunched.loginOptions.map(\.publicID), ["AAAA0001", "BBBB0002"])
    }
}
