import SwiftData
import SwiftUI

struct OnboardingView: View {
    private enum Step { case name, notifications, location }

    @Environment(\.modelContext) private var context
    @State private var step = Step.name
    @State private var name = ""
    @State private var shareLocation = false
    @State private var locationDenied = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            switch step {
            case .name: nameStep
            case .notifications: notificationsStep
            case .location: locationStep
            }
            Spacer()
        }
        .padding(24)
        .animation(.default, value: step)
        .alert("Couldn't finish setup", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var nameStep: some View {
        VStack(spacing: 16) {
            header("heart.circle.fill", "StillAlive?", "A tiny daily check-in so the people you love know you're okay. No account needed.")
            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .textContentType(.givenName)
                .submitLabel(.continue)
            primaryButton("Continue") { step = .notifications }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var notificationsStep: some View {
        VStack(spacing: 16) {
            header("bell.badge.fill", "Check-in reminders", "At each check-in time an alarm rings. Tap Check in and solve a quick puzzle. Reminder notifications follow until you do.")
            primaryButton("Enable alarms and notifications") {
                Task {
                    if #available(iOS 26.0, *) {
                        _ = await AlarmService.shared.requestAuthorization()
                    }
                    _ = await NotificationService.shared.requestAuthorization()
                    step = .location
                }
            }
        }
    }

    private var locationStep: some View {
        VStack(spacing: 16) {
            header("location.circle.fill", "Location (optional)", "Attach your approximate location to check-ins. Off by default; you choose which partners see it.")
            Toggle("Attach location to check-ins", isOn: $shareLocation)
                .onChange(of: shareLocation) { _, enabled in
                    guard enabled else { return }
                    Task {
                        let granted = await LocationService.shared.requestPermission()
                        shareLocation = granted
                        locationDenied = !granted
                    }
                }
            if locationDenied {
                Text("Location access was not allowed. You can change this later in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            primaryButton("Finish", action: finish)
        }
    }

    private func header(_ symbol: String, _ title: String, _ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(title).font(.largeTitle.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func finish() {
        do {
            let identity = try IdentityService.loadOrCreate()
            let settings = context.fetchOrCreateSettings()
            settings.shareLocation = shareLocation
            context.insert(LocalUser(id: identity.publicID, displayName: name.trimmingCharacters(in: .whitespaces)))
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
