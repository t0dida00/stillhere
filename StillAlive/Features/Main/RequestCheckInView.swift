import SwiftUI

/// Shown on a partner's Check-In view when their latest check-in was missed. Holding the
/// button for 3 seconds asks them to check in; then it rests for `MissedAlertRule.requestCooldown`.
struct RequestCheckInView: View {
    @Bindable var partner: Partnership

    var body: some View {
        // Re-evaluates the cooldown every 30 seconds so the button comes back on its own.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if MissedAlertRule.canRequestCheckIn(lastRequestAt: partner.lastCheckInRequestAt, now: context.date) {
                HoldToConfirmButton(title: "Request a check-in", subtitle: "Hold for 3 seconds", duration: 3) {
                    send()
                }
            } else if let sentAt = partner.lastCheckInRequestAt {
                Label {
                    Text("Check-in requested from \(partner.displayName) · \(sentAt.formatted(.relative(presentation: .named)))")
                } icon: {
                    Image(systemName: "paperplane.fill")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func send() {
        partner.lastCheckInRequestAt = .now
        try? partner.modelContext?.save()
        let partnerID = partner.partnerID
        Task { try? await Sync.shared.requestCheckIn(from: partnerID) }
    }
}

/// A full-width red button that only fires after being held for `duration`. A darker band
/// fills from left to right while held; letting go early rewinds it.
struct HoldToConfirmButton: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var duration: Double = 3
    var action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var fired = 0
    /// Set when the hold reached `duration`. `progress` can't tell: it jumps to 1 as soon as
    /// the fill animation starts, even though the band is still drawing.
    @State private var completed = false

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Color.red
                    Color.black.opacity(0.28)
                        .frame(width: proxy.size.width * progress)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 30) {
            completed = true
            fired += 1
            action()
            withAnimation(.easeOut(duration: 0.3).delay(0.2)) { progress = 0 }
        } onPressingChanged: { pressing in
            if pressing {
                completed = false
                withAnimation(.linear(duration: duration)) { progress = 1 }
            } else if !completed {
                // Let go early: rewind from wherever the band has reached.
                withAnimation(.easeOut(duration: 0.25)) { progress = 0 }
            }
        }
        .sensoryFeedback(.success, trigger: fired)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
