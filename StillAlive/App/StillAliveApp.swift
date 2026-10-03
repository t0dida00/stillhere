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
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(AppRouter.Tab.settings)
                    MainView()
                        .tabItem { Label("Main", systemImage: "calendar") }
                        .tag(AppRouter.Tab.main)
                    UsersView()
                        .tabItem { Label("Users", systemImage: "person.2") }
                        .tag(AppRouter.Tab.users)
                }
                .fullScreenCover(item: $router.presentedCheckIn) { key in
                    CheckInView(slotKey: key)
                }
            }
        }
        // Re-runs on foreground and after onboarding. The puzzle shows first; rescheduling follows.
        .task(id: "\(scenePhase)|\(users.count)") {
            guard scenePhase == .active, !users.isEmpty else { return }
            let service = CheckInService(context: context)
            present(service.openSlot(preferring: takeRequestedSlot()))
            await service.reschedule()
            await service.recordLastLocation()
            await service.backfillPlaceNames()
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
