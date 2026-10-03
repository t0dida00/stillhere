import Foundation
import SwiftData

/// One alert shown in the Notifications tab. Saved when the system notification is sent,
/// so the history stays after the banner is gone.
@Model
final class AlertRecord {
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
}
