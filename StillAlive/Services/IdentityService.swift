import Foundation
import Security

struct Identity: Equatable {
    /// Short public ID used as the invite code.
    let publicID: String
    /// 32 random bytes; only ever used to authenticate sync requests.
    let secret: Data
}

enum IdentityError: Error {
    case randomFailed
    case keychain(OSStatus)
}

/// Generates and stores the device identity in the Keychain, synced through iCloud Keychain.
enum IdentityService {
    private static let service = "dev.khoa.stillalive.identity"
    private static let publicIDAccount = "publicID"
    private static let secretAccount = "secret"

    /// Crockford base32 (no I, L, O, U) so codes are easy to read aloud.
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func loadOrCreate() throws -> Identity {
        if let idData = read(account: publicIDAccount),
           let publicID = String(data: idData, encoding: .utf8),
           let secret = read(account: secretAccount) {
            return Identity(publicID: publicID, secret: secret)
        }
        let identity = Identity(publicID: try generatePublicID(), secret: try randomBytes(32))
        try write(Data(identity.publicID.utf8), account: publicIDAccount)
        try write(identity.secret, account: secretAccount)
        return identity
    }

    static let codeLength = 8

    /// Cleans up a typed or pasted invite code: uppercases it, drops spaces and dashes, and reads
    /// the letters Crockford base32 leaves out as the digits they look like (O → 0, I/L → 1).
    static func normalizeCode(_ raw: String) -> String {
        let allowed = Set(alphabet)
        let mapped = raw.uppercased().compactMap { char -> Character? in
            switch char {
            case "O": "0"
            case "I", "L": "1"
            default: allowed.contains(char) ? char : nil
            }
        }
        return String(mapped.prefix(codeLength))
    }

    static func isValidCode(_ code: String) -> Bool {
        code.count == codeLength && code.allSatisfy(Set(alphabet).contains)
    }

    static func generatePublicID(length: Int = codeLength) throws -> String {
        // 256 is a multiple of 32, so `% 32` has no modulo bias.
        String(try randomBytes(length).map { alphabet[Int($0) % alphabet.count] })
    }

    private static func randomBytes(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw IdentityError.randomFailed
        }
        return Data(bytes)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func write(_ data: Data, account: String) throws {
        var deleteQuery = baseQuery(account: account)
        deleteQuery[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(deleteQuery as CFDictionary)

        var query = baseQuery(account: account)
        query[kSecAttrSynchronizable as String] = true
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw IdentityError.keychain(status) }
    }
}
