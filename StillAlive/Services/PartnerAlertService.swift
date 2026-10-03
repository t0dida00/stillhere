import Foundation
import SwiftData

/// Notifies me of each partner's missed check-ins. Runs on the phone while partners are
/// simulated; with the backend, a server push replaces it (SPEC §9).
@MainActor
struct PartnerAlertService {
    let context: ModelContext
    var sync: any SyncService = Sync.shared
    var notifications: NotificationService = .shared

    func checkForMisses(now: Date = .now) async {
        guard let user = context.fetchUser() else { return }
        let partners = ((try? context.fetch(FetchDescriptor<Partnership>())) ?? []).filter(\.isAccepted)
        for partner in partners {
            // The first check only sets the starting point, so old history doesn't flood me.
            guard let since = partner.lastMissCheckAt else {
                partner.lastMissCheckAt = now
                continue
            }
            let slots = (try? await sync.pull(partnerID: partner.partnerID)) ?? []
            for slot in MissedAlertRule.newMisses(slots, since: since, now: now) {
                let id = AlertRecord.identifier(partnerID: partner.partnerID, dayKey: slot.dayKey, slotIndex: slot.slotIndex)
                let saved = (try? context.fetchCount(FetchDescriptor<AlertRecord>(predicate: #Predicate { $0.id == id }))) ?? 0
                guard saved == 0 else { continue }
                context.insert(AlertRecord(id: id, partnerID: partner.partnerID, partnerName: partner.displayName,
                                           dayKey: slot.dayKey, slotIndex: slot.slotIndex, scheduledAt: slot.scheduledAt, createdAt: now))
                await notifications.notifyPartnerMissed(partnerID: partner.partnerID, name: partner.displayName,
                                                        slot: slot, timeZone: user.timeZone)
            }
            partner.lastMissCheckAt = now
        }
        try? context.save()
    }
}
