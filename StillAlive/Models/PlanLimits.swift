import Foundation

/// Free-plan limits, in one place so a future Premium plan only changes them here.
enum PlanLimits {
    static let partners = 3
    static let emergencyContacts = 3
    static let checkInTimes = 3

    /// Accepted partners plus invites I've sent that are still waiting, since each of those
    /// becomes a partner when accepted.
    static func partnerSlotsUsed(_ partnerships: [Partnership]) -> Int {
        partnerships.filter { $0.isAccepted || (!$0.isIncoming && $0.status == "pending") }.count
    }

    static func canAddPartner(_ partnerships: [Partnership]) -> Bool {
        partnerSlotsUsed(partnerships) < partners
    }
}
