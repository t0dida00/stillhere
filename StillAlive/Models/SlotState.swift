import Foundation

enum SlotState: String, Codable, CaseIterable {
    case pending, checkedIn, skipped, missed
}
