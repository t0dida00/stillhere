import Foundation
import SwiftData

@Model
final class LocalUser {
    /// Public shareable ID (invite code).
    var id: String
    var displayName: String
    var timeZoneID: String
    var createdAt: Date
    /// Where the app was last used, saved only while location sharing is on.
    var lastLatitude: Double?
    var lastLongitude: Double?
    var lastPlaceName: String?
    var lastLocationAt: Date?
    /// Small square JPEG; nil shows initials.
    @Attribute(.externalStorage) var avatarData: Data?
    /// JSON of `[EmergencyContact]`; use `emergencyContacts`.
    var emergencyContactsData: Data?

    init(id: String, displayName: String, timeZoneID: String = TimeZone.current.identifier, createdAt: Date = .now) {
        self.id = id
        self.displayName = displayName
        self.timeZoneID = timeZoneID
        self.createdAt = createdAt
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    var emergencyContacts: [EmergencyContact] {
        get { emergencyContactsData.flatMap { try? JSONDecoder().decode([EmergencyContact].self, from: $0) } ?? [] }
        set { emergencyContactsData = try? JSONEncoder().encode(Array(newValue.prefix(EmergencyContact.maxCount))) }
    }
}
