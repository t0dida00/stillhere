import SwiftData
import SwiftUI

@main
struct StillAliveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// The animated opening screen, on cold start only. The app loads underneath it.
    @State private var showSplash = true
    @State private var accounts = AccountStore.shared

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if accounts.isLoggedOut {
                        LoggedOutView()
                    } else {
                        // A new identity per account, so switching accounts starts fresh queries and tasks.
                        RootView()
                            .id(accounts.current)
                            .modelContainer(accounts.container)
                    }
                }
                .environment(AppRouter.shared)
                .environment(accounts)
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(UIAccessibility.isReduceMotionEnabled ? 700 : 2200))
                withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
            }
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router
    @Environment(AccountStore.self) private var accounts
    @Query private var users: [LocalUser]
    @Query(filter: #Predicate<AlertRecord> { !$0.isRead }) private var unreadAlerts: [AlertRecord]

    var body: some View {
        @Bindable var router = router
        Group {
            if users.isEmpty {
                OnboardingView(onCancel: cancelOnboarding)
            } else {
                TabView(selection: $router.selectedTab) {
                    GlobeMapView()
                        .tabItem { Label("Map", systemImage: "globe") }
                        .tag(AppRouter.Tab.map)
                    MainView()
                        .tabItem { Label("Check-In", systemImage: "calendar.badge.checkmark") }
                        .tag(AppRouter.Tab.main)
                    NotificationsView()
                        .tabItem { Label("Notifications", systemImage: "bell") }
                        .badge(unreadAlerts.count)
                        .tag(AppRouter.Tab.notifications)
                    UsersView()
                        .tabItem { Label("Users", systemImage: "person.2") }
                        .tag(AppRouter.Tab.users)
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(AppRouter.Tab.settings)
                }
                .fullScreenCover(item: $router.presentedCheckIn) { target in
                    CheckInView(target: target)
                }
            }
        }
        // Keeps the log-in list's name and ID current.
        .onChange(of: userSignature, initial: true) { recordAccount() }
        // Opening an alert's system notification marks it read in the Notifications tab.
        .onChange(of: router.openedAlertID) { _, id in
            guard let id else { return }
            router.openedAlertID = nil
            let descriptor = FetchDescriptor<AlertRecord>(predicate: #Predicate { $0.id == id })
            (try? context.fetch(descriptor))?.forEach { $0.isRead = true }
            try? context.save()
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
            #if DEBUG
            MockScenario.apply(context: context)
            #endif
            let service = CheckInService(context: context)
            present(service.openSlot(preferring: takeRequestedSlot()))
            await service.reschedule()
            await service.recordLastLocation()
            await service.backfillPlaceNames()
            await PartnerAlertService(context: context).checkForMisses()
            await showCheckInRequest()
        }
        // Keeps the last location and partner miss alerts fresh while the app is open; stops when it leaves the foreground.
        .task(id: scenePhase) {
            guard scenePhase == .active, !users.isEmpty else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: CheckInService.locationRefreshInterval)
                guard !Task.isCancelled else { return }
                await CheckInService(context: context).recordLastLocation()
                await PartnerAlertService(context: context).checkForMisses()
                await showCheckInRequest()
            }
        }
        // A partner's request opened from its notification.
        .onChange(of: router.requestedCheckInRequestID) { _, id in
            guard let id, scenePhase == .active, !users.isEmpty else { return }
            router.requestedCheckInRequestID = nil
            if let request = CheckInRequestService(context: context).request(id: id), request.isOpen {
                presentTarget(.request(id: request.id, from: request.partnerName))
            }
        }
        // Notification or alarm tap while already active.
        .onChange(of: router.requestedSlot) {
            guard scenePhase == .active, !users.isEmpty, let requested = takeRequestedSlot() else { return }
            present(CheckInService(context: context).openSlot(preferring: requested))
        }
    }

    private var cancelOnboarding: (() -> Void)? {
        guard accounts.canCancelNewAccount else { return nil }
        return { accounts.cancelNewAccount() }
    }

    private var userSignature: String {
        users.first.map { "\($0.id)|\($0.displayName)" } ?? ""
    }

    private func recordAccount() {
        guard let user = users.first else { return }
        accounts.record(publicID: user.id, displayName: user.displayName)
    }

    private func takeRequestedSlot() -> SlotKey? {
        defer { router.requestedSlot = nil }
        return router.requestedSlot
    }

    /// Picks up new requests from partners and, when nothing else is showing, opens the puzzle
    /// for the oldest one still open.
    private func showCheckInRequest() async {
        let requests = CheckInRequestService(context: context)
        await requests.fetchNew()
        let opened = router.requestedCheckInRequestID.flatMap(requests.request(id:))
        router.requestedCheckInRequestID = nil
        if let request = opened?.isOpen == true ? opened : requests.oldestOpen() {
            presentTarget(.request(id: request.id, from: request.partnerName))
        }
    }

    private func present(_ key: SlotKey?) {
        presentTarget(key.map(CheckInTarget.slot))
    }

    private func presentTarget(_ target: CheckInTarget?) {
        guard router.presentedCheckIn == nil, let key = target else { return }
        router.selectedTab = .main
        router.presentedCheckIn = key
    }
}
