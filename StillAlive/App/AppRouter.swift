import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    enum Tab: Hashable {
        case map, main, users, settings
    }

    var selectedTab: Tab = .main
    /// The slot whose check-in screen is showing.
    var presentedCheckIn: SlotKey?
    /// Set by a notification tap; consumed by `RootView`.
    var requestedSlot: SlotKey?
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Notification tap → open the check-in screen for that slot.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let key = SlotKey(userInfo: response.notification.request.content.userInfo) else { return }
        await MainActor.run { AppRouter.shared.requestedSlot = key }
    }

    /// While the app is open, go straight to the puzzle instead of showing a banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard let key = SlotKey(userInfo: notification.request.content.userInfo) else { return [.banner, .sound] }
        await MainActor.run { AppRouter.shared.requestedSlot = key }
        return [.sound]
    }
}
