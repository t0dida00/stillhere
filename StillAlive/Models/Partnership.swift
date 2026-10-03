import Foundation
import SwiftData

@Model
final class Partnership {
    var partnerID: String
    var partnerName: String
    /// pending, accepted, declined
    var status: String
    /// What *I* share with them.
    var canSeeLocation: Bool
    var createdAt: Date
    /// True when they asked to see my check-ins; false when I added them.
    var isIncoming: Bool = false
    /// What I call them; shown instead of `partnerName` when set.
    var nickname: String?

    init(partnerID: String, partnerName: String, status: String = "pending", canSeeLocation: Bool = false, createdAt: Date = .now, isIncoming: Bool = false) {
        self.partnerID = partnerID
        self.partnerName = partnerName
        self.status = status
        self.canSeeLocation = canSeeLocation
        self.createdAt = createdAt
        self.isIncoming = isIncoming
    }

    var isAccepted: Bool { status == "accepted" }

    var displayName: String { nickname ?? partnerName }
}
