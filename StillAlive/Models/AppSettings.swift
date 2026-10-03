import Foundation
import SwiftData

@Model
final class AppSettings {
    /// Minutes from midnight in the user's time zone.
    var slotTimes: [Int]
    var graceMinutes: Int
    /// 1...3
    var difficulty: Int
    var shareLocation: Bool
    var remindEveryMinutes: Int

    init(slotTimes: [Int] = [540], graceMinutes: Int = 60, difficulty: Int = 1, shareLocation: Bool = false, remindEveryMinutes: Int = 10) {
        self.slotTimes = slotTimes
        self.graceMinutes = graceMinutes
        self.difficulty = difficulty
        self.shareLocation = shareLocation
        self.remindEveryMinutes = remindEveryMinutes
    }
}

extension ModelContext {
    func fetchUser() -> LocalUser? {
        try? fetch(FetchDescriptor<LocalUser>()).first
    }

    func fetchOrCreateSettings() -> AppSettings {
        if let settings = try? fetch(FetchDescriptor<AppSettings>()).first {
            return settings
        }
        let settings = AppSettings()
        insert(settings)
        return settings
    }
}
