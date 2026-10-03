import Foundation
import SwiftData

/// One alert shown in the Notifications tab. Saved when the system notification is sent,
/// so the history stays after the banner is gone.
@Model
final class AlertRecord {
    enum Kind: String {
        /// A partner missed a check-in.
        case partnerMissed
        /// A partner asked me to check in.
        case checkInRequest
    }

    /// Same as the system notification's identifier, so an alert is saved once.
    @Attribute(.unique) var id: String
    var partnerID: String
    /// The partner's name when the alert was sent, in case they're removed later.
    var partnerName: String
    var dayKey: String
    var slotIndex: Int
    var scheduledAt: Date
    var createdAt: Date
    var isRead: Bool
    /// `Kind`; alerts saved before kinds existed are missed check-ins.
    var kindRaw: String = Kind.partnerMissed.rawValue
    /// For `.checkInRequest`: the `CheckInRequest.id`.
    var requestID: String?

    var kind: Kind { Kind(rawValue: kindRaw) ?? .partnerMissed }

    init(id: String, partnerID: String, partnerName: String, dayKey: String, slotIndex: Int, scheduledAt: Date,
         createdAt: Date = .now, isRead: Bool = false) {
        self.id = id
        self.partnerID = partnerID
        self.partnerName = partnerName
        self.dayKey = dayKey
        self.slotIndex = slotIndex
        self.scheduledAt = scheduledAt
        self.createdAt = createdAt
        self.isRead = isRead
    }

    static func identifier(partnerID: String, dayKey: String, slotIndex: Int) -> String {
        "partner-miss.\(partnerID).\(dayKey)#\(slotIndex)"
    }

    static func identifier(requestID: String) -> String {
        "checkin-request.\(requestID)"
    }
}
