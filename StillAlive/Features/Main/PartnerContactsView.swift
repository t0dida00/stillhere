import SwiftUI
import UIKit

/// A partner's emergency contacts, opened by holding their avatar on Check-In.
/// Each can be copied or opened in its app.
struct PartnerContactsView: View {
    let name: String
    let partnerID: String

    @Environment(\.dismiss) private var dismiss
    @State private var contacts: [EmergencyContact]?
    @State private var copiedID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if let contacts, contacts.isEmpty {
                    ContentUnavailableView("No emergency contacts",
                                           systemImage: "cross.case",
                                           description: Text("\(name) hasn't added any emergency contacts yet."))
                } else if let contacts {
                    List {
                        Section {
                            ForEach(contacts) { contact in
                                row(contact)
                            }
                        } footer: {
                            Text("Copy a number or username, or open it in its app.")
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("\(name)'s emergency contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                contacts = (try? await Sync.shared.emergencyContacts(of: partnerID)) ?? []
            }
        }
    }

    private func row(_ contact: EmergencyContact) -> some View {
        HStack(spacing: 12) {
            ContactAppIcon(kind: contact.kind)
            VStack(alignment: .leading, spacing: 1) {
                Text(contact.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(contact.value)
                    .font(.body.monospacedDigit())
                    .textSelection(.enabled)
            }
            Spacer()
            Button {
                copy(contact)
            } label: {
                RoundIcon(systemName: copiedID == contact.id ? "checkmark" : "doc.on.doc",
                          tint: copiedID == contact.id ? .green : .accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(copiedID == contact.id ? Text("Copied") : Text("Copy"))
            if let url = contact.url {
                Link(destination: url) {
                    RoundIcon(systemName: "arrow.up.forward", tint: .accentColor)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open in \(contact.kind.title)")
            }
        }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { copy(contact) }
        }
    }

    private func copy(_ contact: EmergencyContact) {
        UIPasteboard.general.string = contact.value
        copiedID = contact.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedID == contact.id { copiedID = nil }
        }
    }
}

/// Copy and Open share this look: an accent icon on a light circle of the same color.
private struct RoundIcon: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.14), in: Circle())
            .contentTransition(.symbolEffect(.replace))
            .animation(.default, value: systemName)
    }
}
