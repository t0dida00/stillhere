import SwiftData
import SwiftUI

@main
struct StillAliveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppRouter.shared)
        }
        .modelContainer(for: [LocalUser.self, CheckInSlot.self, Partnership.self, AppSettings.self])
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router
    @Query private var users: [LocalUser]

    var body: some View {
        @Bindable var router = router
        Group {
            if users.isEmpty {
                OnboardingView()
            } else {
                TabView(selection: $router.selectedTab) {
                    GlobeMapView()
                        .tabItem { Label("Map", systemImage: "globe") }
                        .tag(AppRouter.Tab.map)
                    MainView()
                        .tabItem { Label("Check-In", systemImage: "calendar.badge.checkmark") }
                        .tag(AppRouter.Tab.main)
                    UsersView()
                        .tabItem { Label("Users", systemImage: "person.2") }
                        .tag(AppRouter.Tab.users)
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(AppRouter.Tab.settings)
                }
                .fullScreenCover(item: $router.presentedCheckIn) { key in
                    CheckInView(slotKey: key)
                }
            }
        }
        // Invite link, e.g. from scanning a QR code with the Camera app.
        .onOpenURL { url in
            guard !users.isEmpty, let code = IdentityService.code(fromScanned: url.absoluteString) else { return }
            router.selectedTab = .users
            router.pendingInviteCode = code
        }
        // Re-runs on foreground and after onboarding. The puzzle shows first; rescheduling follows.
        .task(id: "\(scenePhase)|\(users.count)") {
            guard scenePhase == .active, !users.isEmpty else { return }
            let service = CheckInService(context: context)
            present(service.openSlot(preferring: takeRequestedSlot()))
            await service.reschedule()
            await service.recordLastLocation()
            await service.backfillPlaceNames()
            await PartnerAlertService(context: context).checkForMisses()
        }
        // Keeps the last location and partner miss alerts fresh while the app is open; stops when it leaves the foreground.
        .task(id: scenePhase) {
            guard scenePhase == .active, !users.isEmpty else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: CheckInService.locationRefreshInterval)
                guard !Task.isCancelled else { return }
                await CheckInService(context: context).recordLastLocation()
                await PartnerAlertService(context: context).checkForMisses()
            }
        }
        // Notification or alarm tap while already active.
        .onChange(of: router.requestedSlot) {
            guard scenePhase == .active, !users.isEmpty, let requested = takeRequestedSlot() else { return }
            present(CheckInService(context: context).openSlot(preferring: requested))
        }
    }

    private func takeRequestedSlot() -> SlotKey? {
        defer { router.requestedSlot = nil }
        return router.requestedSlot
    }

    private func present(_ key: SlotKey?) {
        guard router.presentedCheckIn == nil, let key else { return }
        router.selectedTab = .main
        router.presentedCheckIn = key
    }
}
