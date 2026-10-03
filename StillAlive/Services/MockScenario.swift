#if DEBUG
import Foundation
import SwiftData

/// Debug-only test partners from launch arguments, e.g.
/// `-mockPartner "Dad@04:28/1"`: an accepted partner "Dad" checking in daily at 04:28 with a
/// 1-minute grace window, who misses every check-in from the start of today. Repeat the
/// argument for more partners. Running it again with the same name updates that partner.
@MainActor
enum MockScenario {
    static func apply(context: ModelContext, arguments: [String] = ProcessInfo.processInfo.arguments, now: Date = .now) {
        let specs = zip(arguments, arguments.dropFirst()).filter { $0.0 == "-mockPartner" }.map(\.1)
        guard !specs.isEmpty, let user = context.fetchUser() else { return }
        let startOfToday = DayKey.calendar(in: user.timeZone).startOfDay(for: now)
        let existing = (try? context.fetch(FetchDescriptor<Partnership>())) ?? []
        var schedules = MockSchedule.saved

        for spec in specs {
            guard let (name, minutes, grace) = parse(spec) else { continue }
            let partner = existing.first { $0.partnerName == name } ?? {
                let code = (try? IdentityService.generatePublicID()) ?? UUID().uuidString.prefix(8).uppercased()
                let new = Partnership(partnerID: code, partnerName: name, status: "accepted")
                context.insert(new)
                return new
            }()
            partner.status = "accepted"
            // Checking from the start of today means today's misses are notified.
            partner.lastMissCheckAt = startOfToday
            schedules[partner.partnerID] = MockSchedule(slotTimes: [minutes], graceMinutes: grace, missesFrom: startOfToday)
        }
        MockSchedule.saved = schedules
        try? context.save()
    }

    /// "Dad@04:28/1" → ("Dad", 268, 1).
    static func parse(_ spec: String) -> (name: String, minutes: Int, grace: Int)? {
        let parts = spec.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let timeAndGrace = parts[1].split(separator: "/")
        let clock = timeAndGrace[0].split(separator: ":").compactMap { Int($0) }
        guard clock.count == 2, (0..<24).contains(clock[0]), (0..<60).contains(clock[1]) else { return nil }
        let grace = timeAndGrace.count > 1 ? Int(timeAndGrace[1]) ?? 60 : 60
        return (String(parts[0]), clock[0] * 60 + clock[1], max(1, grace))
    }
}
#endif
