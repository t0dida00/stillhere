import Foundation
import Observation
import SwiftData

/// An account on this device. Each has its own SwiftData store and Keychain identity.
struct Account: Codable, Hashable, Identifiable {
    /// Names the account's store file and Keychain entries.
    let key: String
    /// Public ID; nil until onboarding finishes.
    var publicID: String?
    var displayName: String

    var id: String { key }
}

/// The accounts on this device, which one is in use, and whether the user is logged out.
/// Saved in UserDefaults. Logging out keeps every account's data; logging in switches stores.
@MainActor
@Observable
final class AccountStore {
    static let shared = AccountStore()

    /// The original account. Its store and Keychain entries keep their pre-accounts names so existing data carries over.
    static let defaultKey = "default"

    private static let accountsKey = "accounts"
    private static let currentKey = "currentAccount"
    private static let loggedOutKey = "loggedOut"

    private let defaults: UserDefaults
    private let makeContainer: (String) -> ModelContainer

    private(set) var accounts: [Account] {
        didSet { defaults.set(try? JSONEncoder().encode(accounts), forKey: Self.accountsKey) }
    }
    private(set) var current: String {
        didSet {
            defaults.set(current, forKey: Self.currentKey)
            container = makeContainer(current)
        }
    }
    private(set) var isLoggedOut: Bool {
        didSet { defaults.set(isLoggedOut, forKey: Self.loggedOutKey) }
    }
    /// The current account's store.
    private(set) var container: ModelContainer

    init(defaults: UserDefaults = .standard, makeContainer: @escaping (String) -> ModelContainer = AccountStore.container(for:)) {
        self.defaults = defaults
        self.makeContainer = makeContainer
        let saved = defaults.data(forKey: Self.accountsKey).flatMap { try? JSONDecoder().decode([Account].self, from: $0) } ?? []
        let accounts = saved.isEmpty ? [Account(key: Self.defaultKey, displayName: "")] : saved
        let current = defaults.string(forKey: Self.currentKey).flatMap { key in accounts.contains { $0.key == key } ? key : nil }
            ?? accounts[0].key
        self.accounts = accounts
        self.current = current
        self.isLoggedOut = defaults.bool(forKey: Self.loggedOutKey)
        self.container = makeContainer(current)
        // First run with accounts: name the existing account from its stored user.
        if saved.isEmpty, let user = container.mainContext.fetchUser() {
            record(publicID: user.id, displayName: user.displayName)
        }
    }

    /// Accounts that finished onboarding, for the log-in list.
    var loginOptions: [Account] { accounts.filter { $0.publicID != nil } }

    /// A new account in onboarding can go back to the log-in list when there is another account to use.
    var canCancelNewAccount: Bool {
        accounts.first { $0.key == current }?.publicID == nil && !loginOptions.isEmpty
    }

    /// Keeps the log-in list's name and ID in step with the current account's user.
    func record(publicID: String, displayName: String) {
        guard let index = accounts.firstIndex(where: { $0.key == current }),
              accounts[index].publicID != publicID || accounts[index].displayName != displayName else { return }
        accounts[index].publicID = publicID
        accounts[index].displayName = displayName
    }

    /// Callers cancel the current account's alarms and reminders first.
    func logOut() {
        isLoggedOut = true
    }

    func logIn(_ account: Account) {
        guard accounts.contains(where: { $0.key == account.key }) else { return }
        if current != account.key { current = account.key }
        isLoggedOut = false
    }

    /// Switches to a new, empty account, which starts with onboarding.
    func createAccount() {
        let account = Account(key: UUID().uuidString, displayName: "")
        accounts.append(account)
        current = account.key
        isLoggedOut = false
    }

    /// Drops the account being onboarded and returns to the log-in list.
    func cancelNewAccount() {
        guard canCancelNewAccount else { return }
        accounts.removeAll { $0.key == current }
        current = loginOptions[0].key
        isLoggedOut = true
    }

    static let models: [any PersistentModel.Type] = [
        LocalUser.self, CheckInSlot.self, Partnership.self, AppSettings.self, AlertRecord.self, CheckInRequest.self,
    ]

    /// The default account uses SwiftData's default store; others get `account-<key>.store`.
    static func container(for key: String) -> ModelContainer {
        let schema = Schema(models)
        let configuration = key == defaultKey
            ? ModelConfiguration(schema: schema)
            : ModelConfiguration("account-\(key)", schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Couldn't open the store for account \(key): \(error)")
        }
    }
}
