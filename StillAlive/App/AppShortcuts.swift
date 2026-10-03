import AppIntents

/// "Open Check-in" for Shortcuts automations and Siri. Opens the app on Check-In; if a check-in
/// is due, the foreground refresh in `RootView` shows its puzzle.
struct OpenCheckInShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Check-in"
    static let description = IntentDescription("Opens StillAlive? on Check-In. If a check-in is due, its puzzle appears.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.selectedTab = .main
        return .result()
    }
}

struct StillAliveShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenCheckInShortcutIntent(),
            phrases: [
                "Check in with \(.applicationName)",
                "Open \(.applicationName) check-in",
            ],
            shortTitle: "Check In",
            systemImageName: "checkmark.circle"
        )
    }
}
