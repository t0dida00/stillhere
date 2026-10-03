import Foundation
import SwiftData

@Model
final class CheckInSlot {
    /// "yyyy-MM-dd" in the owner's local time zone.
    var dayKey: String
    var slotIndex: Int
    /// UTC instant.
    var scheduledAt: Date
    var stateRaw: String
    var resolvedAt: Date?
    var latitude: Double?
    var longitude: Double?
    /// Short address for the location, e.g. "District 1, Ho Chi Minh City".
    var placeName: String?
    var synced: Bool
    var ownerID: String

    init(ownerID: String, dayKey: String, slotIndex: Int, scheduledAt: Date, state: SlotState = .pending) {
        self.ownerID = ownerID
        self.dayKey = dayKey
        self.slotIndex = slotIndex
        self.scheduledAt = scheduledAt
        self.stateRaw = state.rawValue
        self.synced = false
    }

    var state: SlotState {
        get { SlotState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    var key: SlotKey { SlotKey(dayKey: dayKey, slotIndex: slotIndex) }

    var snapshot: SlotSnapshot { SlotSnapshot(key: key, scheduledAt: scheduledAt, state: state) }
}
