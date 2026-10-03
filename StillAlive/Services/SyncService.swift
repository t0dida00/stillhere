import Foundation

/// A partner's slot as received from the backend.
struct RemoteSlot: Codable, Equatable {
    var ownerID: String
    var dayKey: String
    var slotIndex: Int
    var scheduledAt: Date
    var state: SlotState
    var resolvedAt: Date?
    var latitude: Double?
    var longitude: Double?
    var placeName: String?
}

protocol SyncService {
    func push(_ slots: [CheckInSlot]) async throws
    func pull(partnerID: String) async throws -> [RemoteSlot]
    func sendInvite(to partnerID: String) async throws
    func respond(to partnerID: String, accept: Bool) async throws
    /// Whether the partner turned on location sharing for me.
    func partnerSharesLocation(_ partnerID: String) async throws -> Bool
    /// The emergency contacts the partner added, for reaching them when they miss check-ins.
    func emergencyContacts(of partnerID: String) async throws -> [EmergencyContact]
}

/// The app's sync service. Mock partners until the backend exists (Phase 3).
enum Sync {
    static let shared: any SyncService = MockSyncService()
}

/// Used until the backend exists (Phase 3). Everything stays local.
struct NoopSyncService: SyncService {
    func push(_ slots: [CheckInSlot]) async throws {}
    func pull(partnerID: String) async throws -> [RemoteSlot] { [] }
    func sendInvite(to partnerID: String) async throws {}
    func respond(to partnerID: String, accept: Bool) async throws {}
    func partnerSharesLocation(_ partnerID: String) async throws -> Bool { false }
    func emergencyContacts(of partnerID: String) async throws -> [EmergencyContact] { [] }
}

/// A test partner's own schedule for `MockSyncService`, saved on this phone. Used by debug
/// builds' `-mockPartner` launch option (see `MockScenario`).
struct MockSchedule: Codable {
    var slotTimes: [Int]
    var graceMinutes: Int
    /// Every check-in scheduled from here on is missed.
    var missesFrom: Date?

    private static let key = "mockSchedules"

    static var saved: [String: MockSchedule] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
            return (try? JSONDecoder().decode([String: MockSchedule].self, from: data)) ?? [:]
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key)
        }
    }
}

/// Phase 2 stand-in: every partner has a made-up history that stays the same across launches,
/// and invites are accepted at once.
struct MockSyncService: SyncService {
    var timeZone: TimeZone = .current

    func push(_ slots: [CheckInSlot]) async throws {}

    func pull(partnerID: String) async throws -> [RemoteSlot] {
        if let schedule = MockSchedule.saved[partnerID] {
            return Self.history(for: partnerID, now: .now, timeZone: timeZone, slotTimes: schedule.slotTimes,
                                graceMinutes: schedule.graceMinutes, sharesLocation: Self.sharesLocation(partnerID),
                                missesFrom: schedule.missesFrom)
        }
        return Self.history(for: partnerID, now: .now, timeZone: timeZone, sharesLocation: Self.sharesLocation(partnerID))
    }

    func partnerSharesLocation(_ partnerID: String) async throws -> Bool {
        Self.sharesLocation(partnerID)
    }

    func emergencyContacts(of partnerID: String) async throws -> [EmergencyContact] {
        Self.emergencyContacts(for: partnerID)
    }

    /// 0 to `PlanLimits.emergencyContacts` made-up contacts per partner, the same every time:
    /// a Vietnamese mobile number as Phone, Zalo or WhatsApp, or a Telegram username.
    static func emergencyContacts(for partnerID: String) -> [EmergencyContact] {
        var rng = SplitMix64(seed: PuzzleGenerator.seed(dayKey: "\(partnerID)|contacts", slotIndex: 0))
        let count = rng.int(in: 0...PlanLimits.emergencyContacts)
        let kinds = EmergencyContact.Kind.allCases
        return (0..<count).map { index in
            let kind = index == 0 ? .phone : kinds[rng.int(in: 0...(kinds.count - 1))]
            let number = "+84 9\(rng.int(in: 10...99)) \(rng.int(in: 100...999)) \(rng.int(in: 100...999))"
            return EmergencyContact(kind: kind, value: kind == .telegram ? "@" + partnerID.lowercased() : number)
        }
    }

    /// Mock rule that's easy to predict when testing: partners whose code ends in a digit share their location.
    static func sharesLocation(_ partnerID: String) -> Bool {
        partnerID.last?.isNumber ?? false
    }

    func sendInvite(to partnerID: String) async throws {}
    func respond(to partnerID: String, accept: Bool) async throws {}

    /// Cities a mock partner can live in; picked per partner so it stays the same.
    static let homes: [(name: String, latitude: Double, longitude: Double)] = [
        ("District 1, Ho Chi Minh City", 10.7769, 106.7009),
        ("Hoàn Kiếm, Hanoi", 21.0285, 105.8542),
        ("Hải Châu, Da Nang", 16.0544, 108.2022),
        ("Shinjuku, Tokyo", 35.6762, 139.6503),
        ("Downtown Core, Singapore", 1.3521, 103.8198),
        ("Le Marais, Paris", 48.8566, 2.3522),
    ]

    /// Two slots a day (09:00, 21:00) for the last `days` days. Past slots are mostly checked in,
    /// with some skips and misses; a slot inside its grace window may still be pending.
    /// Check-ins carry a location within a few kilometres of the partner's home city.
    static func history(for partnerID: String, now: Date, timeZone: TimeZone, days: Int = 60,
                        slotTimes: [Int] = [540, 1260], graceMinutes: Int = 60, sharesLocation: Bool = true,
                        missesFrom: Date? = nil) -> [RemoteSlot] {
        let calendar = DayKey.calendar(in: timeZone)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: now) else { return [] }
        let home = homes[Int(PuzzleGenerator.seed(dayKey: partnerID, slotIndex: 0) % UInt64(homes.count))]
        return SlotPlanner.specs(from: start, through: now, slotTimes: slotTimes, timeZone: timeZone).map { spec in
            var rng = SplitMix64(seed: PuzzleGenerator.seed(dayKey: "\(partnerID)|\(spec.key.dayKey)", slotIndex: spec.key.slotIndex))
            let roll = rng.int(in: 0...99)
            let deadline = SlotRules.deadline(for: spec.scheduledAt, graceMinutes: graceMinutes)
            let state: SlotState
            if spec.scheduledAt > now {
                state = .pending
            } else if let missesFrom, spec.scheduledAt >= missesFrom {
                // A test partner who misses every check-in from this point on.
                state = now < deadline ? .pending : .missed
            } else if now < deadline {
                state = roll < 60 ? .checkedIn : .pending
            } else {
                state = roll < 80 ? .checkedIn : roll < 90 ? .skipped : .missed
            }
            let answeredAt = min(now, spec.scheduledAt.addingTimeInterval(TimeInterval(rng.int(in: 1...max(1, graceMinutes - 1)) * 60)))
            let resolvedAt: Date? = switch state {
            case .checkedIn, .skipped: answeredAt
            case .missed: deadline
            case .pending: nil
            }
            // Up to ±0.02° (about 2 km) from home.
            let jitter = { Double(rng.int(in: -200...200)) / 10_000 }
            let located = sharesLocation && state == .checkedIn
            return RemoteSlot(ownerID: partnerID, dayKey: spec.key.dayKey, slotIndex: spec.key.slotIndex,
                              scheduledAt: spec.scheduledAt, state: state, resolvedAt: resolvedAt,
                              latitude: located ? home.latitude + jitter() : nil,
                              longitude: located ? home.longitude + jitter() : nil,
                              placeName: located ? home.name : nil)
        }
    }
}
