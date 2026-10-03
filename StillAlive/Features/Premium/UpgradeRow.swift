import SwiftUI

/// Shown where adding something would go over a free-plan limit (`PlanLimits`).
/// Premium doesn't exist yet, so it opens `premiumComingSoon`.
struct UpgradeRow: View {
    /// What Premium would give more of, e.g. "for more partners".
    let detail: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text("Upgrade to Premium")
                Spacer()
                Text(detail)
                    .font(.caption)
            }
            .foregroundStyle(.orange)
        }
    }
}

extension View {
    /// The placeholder shown by Upgrade to Premium until Premium exists.
    func premiumComingSoon(isPresented: Binding<Bool>, message: LocalizedStringKey) -> some View {
        alert("Premium is coming soon", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}
