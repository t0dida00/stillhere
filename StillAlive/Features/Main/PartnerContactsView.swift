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
                            Text("Tap Copy to put a number or username on the clipboard.")
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
                Label(copiedID == contact.id ? "Copied" : "Copy",
                      systemImage: copiedID == contact.id ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if let url = contact.url {
                Link(destination: url) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.title3)
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
