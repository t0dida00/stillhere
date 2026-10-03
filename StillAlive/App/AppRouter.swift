import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    enum Tab: Hashable {
        case map, main, notifications, users, settings
    }

    var selectedTab: Tab = .main
    /// What the check-in screen is showing: a slot or a partner's request.
    var presentedCheckIn: CheckInTarget?
    /// Set by a notification tap; consumed by `RootView`.
    var requestedSlot: SlotKey?
    /// Set by an opened invite link; consumed by `UsersView`, which opens Add partner with it.
    var pendingInviteCode: String?
    /// Set by a partner notification tap; consumed by `MainView`, which shows their calendar.
    var requestedPartnerID: String?
    /// The alert opened from a system notification; `RootView` marks it read.
    var openedAlertID: String?
    /// A partner's check-in request opened from its notification; `RootView` shows its puzzle.
    var requestedCheckInRequestID: String?
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Notification tap → open the check-in screen for that slot.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        if let requestID = userInfo["checkInRequestID"] as? String {
            await MainActor.run { AppRouter.shared.requestedCheckInRequestID = requestID }
            return
        }
        if let partnerID = userInfo["partnerID"] as? String {
            await MainActor.run {
                AppRouter.shared.selectedTab = .main
                AppRouter.shared.requestedPartnerID = partnerID
                AppRouter.shared.openedAlertID = userInfo["alertID"] as? String
            }
            return
        }
        guard let key = SlotKey(userInfo: userInfo) else { return }
        await MainActor.run { AppRouter.shared.requestedSlot = key }
    }

    /// While the app is open, go straight to the puzzle instead of showing a banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if let requestID = notification.request.content.userInfo["checkInRequestID"] as? String {
            await MainActor.run { AppRouter.shared.requestedCheckInRequestID = requestID }
            return [.sound]
        }
        guard let key = SlotKey(userInfo: notification.request.content.userInfo) else { return [.banner, .sound] }
        await MainActor.run { AppRouter.shared.requestedSlot = key }
        return [.sound]
    }
}
