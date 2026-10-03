import Foundation
import SwiftData

/// Check-in requests from partners: picks up new ones (with a notification), and answers or
/// sets them aside. Requests arrive through `SyncService.incomingCheckInRequests()`.
@MainActor
struct CheckInRequestService {
    let context: ModelContext
    var sync: any SyncService = Sync.shared
    var notifications: NotificationService = .shared

    /// Saves requests not seen before and notifies me of each. Requests from someone who isn't
    /// an accepted partner are ignored.
    func fetchNew() async {
        let incoming = (try? await sync.incomingCheckInRequests()) ?? []
        guard !incoming.isEmpty else { return }
        let partners = ((try? context.fetch(FetchDescriptor<Partnership>())) ?? []).filter(\.isAccepted)
        for request in incoming {
            let id = request.id
            let known = (try? context.fetchCount(FetchDescriptor<CheckInRequest>(predicate: #Predicate { $0.id == id }))) ?? 0
            guard known == 0, let partner = partners.first(where: { $0.partnerID == request.partnerID }) else { continue }
            context.insert(CheckInRequest(id: id, partnerID: partner.partnerID, partnerName: partner.displayName,
                                          requestedAt: request.requestedAt))
            let alert = AlertRecord(id: AlertRecord.identifier(requestID: id), partnerID: partner.partnerID,
                                    partnerName: partner.displayName, dayKey: "", slotIndex: 0,
                                    scheduledAt: request.requestedAt, createdAt: request.requestedAt)
            alert.kindRaw = AlertRecord.Kind.checkInRequest.rawValue
            alert.requestID = id
            context.insert(alert)
            await notifications.notifyCheckInRequest(id: id, name: partner.displayName)
        }
        try? context.save()
    }

    /// The oldest request I haven't answered or set aside.
    func oldestOpen() -> CheckInRequest? {
        let all = (try? context.fetch(FetchDescriptor<CheckInRequest>(sortBy: [SortDescriptor(\.requestedAt)]))) ?? []
        return all.first(where: \.isOpen)
    }

    func request(id: String) -> CheckInRequest? {
        try? context.fetch(FetchDescriptor<CheckInRequest>(predicate: #Predicate { $0.id == id })).first
    }

    /// Answers every open request: I just showed I'm okay.
    func answerAll(now: Date = .now) {
        let open = ((try? context.fetch(FetchDescriptor<CheckInRequest>())) ?? []).filter(\.isOpen)
        guard !open.isEmpty else { return }
        for request in open {
            request.answeredAt = now
            markAlertRead(requestID: request.id)
            let id = request.id
            Task { try? await sync.answerCheckInRequest(id) }
        }
        try? context.save()
    }

    func dismiss(id: String, now: Date = .now) {
        guard let request = request(id: id), request.isOpen else { return }
        request.dismissedAt = now
        markAlertRead(requestID: id)
        try? context.save()
    }

    /// A handled request needs no attention in the Notifications tab.
    private func markAlertRead(requestID: String) {
        let alertID = AlertRecord.identifier(requestID: requestID)
        (try? context.fetch(FetchDescriptor<AlertRecord>(predicate: #Predicate { $0.id == alertID })))?.forEach { $0.isRead = true }
    }
}
