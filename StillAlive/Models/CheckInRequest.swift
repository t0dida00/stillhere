import Foundation
import SwiftData

/// A partner asked me to check in. Open until I answer it (solve the puzzle) or set it aside.
@Model
final class CheckInRequest {
    @Attribute(.unique) var id: String
    var partnerID: String
    /// The partner's name when the request arrived.
    var partnerName: String
    var requestedAt: Date
    var answeredAt: Date?
    /// Set when I chose "Not now", so the popup doesn't keep coming back.
    var dismissedAt: Date?

    init(id: String, partnerID: String, partnerName: String, requestedAt: Date) {
        self.id = id
        self.partnerID = partnerID
        self.partnerName = partnerName
        self.requestedAt = requestedAt
    }

    var isOpen: Bool { answeredAt == nil && dismissedAt == nil }
}

/// What the check-in screen is for: a scheduled slot, or a partner's request.
enum CheckInTarget: Hashable, Identifiable {
    case slot(SlotKey)
    case request(id: String, from: String)

    var id: String {
        switch self {
        case .slot(let key): "slot.\(key.id)"
        case .request(let id, _): "request.\(id)"
        }
    }
}
