import SwiftData
import SwiftUI

/// History of alerts about partners' missed check-ins, newest first.
struct NotificationsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \AlertRecord.createdAt, order: .reverse) private var alerts: [AlertRecord]
    @Query private var partnerships: [Partnership]
    @Query private var users: [LocalUser]

    var body: some View {
        NavigationStack {
            Group {
                if alerts.isEmpty {
                    ContentUnavailableView("No notifications",
                                           systemImage: "bell.slash",
                                           description: Text("When a partner misses a check-in, it shows up here."))
                } else {
                    List {
                        ForEach(alerts) { alert in
                            Button {
                                open(alert)
                            } label: {
                                AlertRow(alert: alert, name: name(for: alert), timeZone: users.first?.timeZone ?? .current)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            offsets.map { alerts[$0] }.forEach(context.delete)
                            try? context.save()
                        }
                    }
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                if alerts.contains(where: { !$0.isRead }) {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Mark all as read") {
                            alerts.forEach { $0.isRead = true }
                            try? context.save()
                        }
                    }
                }
            }
        }
    }

    /// The partner's current name (nickname included), or the saved one if they were removed.
    private func name(for alert: AlertRecord) -> String {
        partnerships.first { $0.partnerID == alert.partnerID }?.displayName ?? alert.partnerName
    }

    private func open(_ alert: AlertRecord) {
        alert.isRead = true
        try? context.save()
        guard partnerships.contains(where: { $0.partnerID == alert.partnerID && $0.isAccepted }) else { return }
        router.selectedTab = .main
        router.requestedPartnerID = alert.partnerID
    }
}

private struct AlertRow: View {
    let alert: AlertRecord
    let name: String
    let timeZone: TimeZone

    private var time: String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return alert.scheduledAt.formatted(style)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(name: name, id: alert.partnerID, size: 40)
                .frame(width: 48, height: 48)
                .background { DayProgressRing(states: [.missed], lineWidth: 2.5, gap: 1) }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(name) missed a check-in")
                    .font(.subheadline.weight(alert.isRead ? .regular : .semibold))
                Text("The \(time) check-in on \(DayKey.display(alert.dayKey)) wasn't done.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(alert.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if !alert.isRead {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)
                    .accessibilityLabel("Unread")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
