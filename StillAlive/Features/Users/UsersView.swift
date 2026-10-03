import PhotosUI
import SwiftData
import SwiftUI

struct UsersView: View {
    @Environment(\.modelContext) private var context
    @Query private var users: [LocalUser]
    @Query(sort: \Partnership.createdAt) private var partnerships: [Partnership]
    @Environment(AppRouter.self) private var router
    @State private var addingPartner = false
    /// Prefilled into Add partner when it opens from an invite link.
    @State private var linkedCode = ""
    @State private var showingQR = false
    /// The emergency contact being added or edited.
    @State private var editingContact: EmergencyContact?

    private var received: [Partnership] { partnerships.filter { $0.isIncoming && $0.status == "pending" } }
    private var sent: [Partnership] { partnerships.filter { !$0.isIncoming && $0.status == "pending" } }
    private var partners: [Partnership] { partnerships.filter { $0.status != "pending" } }

    var body: some View {
        NavigationStack {
            List {
                if let user = users.first {
                    meSection(user)
                }

                Section {
                    if received.isEmpty {
                        Text("No invitations right now.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(received) { request in
                        RequestRow(partnership: request) { accept in respond(to: request, accept: accept) }
                    }
                    Button {
                        addDemoRequest()
                    } label: {
                        Label("Simulate an invitation", systemImage: "person.crop.circle.badge.questionmark")
                    }
                } header: {
                    Text("Requests")
                } footer: {
                    Text("Invitations to join someone's circle. Accepting lets them see your check-ins and you see theirs.")
                }

                if !sent.isEmpty {
                    Section("Sent") {
                        ForEach(sent) { invite in
                            SentRow(partnership: invite) {
                                context.delete(invite)
                                try? context.save()
                            }
                        }
                    }
                }

                Section {
                    ForEach(partners) { partner in
                        PartnerRow(partnership: partner)
                    }
                    .onDelete { offsets in
                        offsets.map { partners[$0] }.forEach(context.delete)
                        try? context.save()
                    }
                    Button {
                        addingPartner = true
                    } label: {
                        Label("Add partner by code", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Partners")
                } footer: {
                    Text("Until sync is available, partners are simulated: invites are accepted after a few seconds and check-ins are made up.")
                }
            }
            .navigationTitle("Users")
            .sheet(isPresented: $addingPartner, onDismiss: { linkedCode = "" }) {
                AddPartnerView(ownCode: users.first?.id ?? "", existingCodes: Set(partnerships.map(\.partnerID)), initialCode: linkedCode)
            }
            .sheet(isPresented: $showingQR) {
                if let user = users.first {
                    InviteQRView(name: user.displayName, code: user.id)
                }
            }
            .onChange(of: router.pendingInviteCode, initial: true) { _, code in
                guard let code else { return }
                router.pendingInviteCode = nil
                linkedCode = code
                addingPartner = true
            }
        }
    }

    private func meSection(_ user: LocalUser) -> some View {
        Section {
            MyAvatarRow(user: user)
            LabeledContent("Invite code") {
                Text(user.id)
                    .font(.body.monospaced().weight(.semibold))
                    .textSelection(.enabled)
            }
            Button {
                showingQR = true
            } label: {
                Label("Show QR code", systemImage: "qrcode")
            }
            ShareLink(item: IdentityService.inviteURL(for: user.id),
                      message: Text("Add me on StillAlive? with code \(user.id)")) {
                Label("Share invite", systemImage: "square.and.arrow.up")
            }

            emergencyContactRows(user)
        } header: {
            Text("Me")
        } footer: {
            Text("Partners use your code to request to see your check-ins. Emergency contacts (up to \(EmergencyContact.maxCount)) help them reach you if you miss check-ins.")
        }
        .sheet(item: $editingContact) { contact in
            EmergencyContactEditor(
                contact: contact,
                isNew: !user.emergencyContacts.contains { $0.id == contact.id },
                onSave: { saved in
                    var contacts = user.emergencyContacts
                    if let index = contacts.firstIndex(where: { $0.id == saved.id }) {
                        contacts[index] = saved
                    } else {
                        contacts.append(saved)
                    }
                    user.emergencyContacts = contacts
                    try? context.save()
                },
                onDelete: {
                    user.emergencyContacts.removeAll { $0.id == contact.id }
                    try? context.save()
                }
            )
        }
    }

    @ViewBuilder
    private func emergencyContactRows(_ user: LocalUser) -> some View {
        let contacts = user.emergencyContacts
        ForEach(contacts) { contact in
            Button {
                editingContact = contact
            } label: {
                EmergencyContactRow(contact: contact)
            }
            .foregroundStyle(.primary)
        }
        .onDelete { offsets in
            var remaining = contacts
            remaining.remove(atOffsets: offsets)
            user.emergencyContacts = remaining
            try? context.save()
        }
        if contacts.count < EmergencyContact.maxCount {
            Button {
                editingContact = EmergencyContact(kind: .phone, value: "")
            } label: {
                Label("Add emergency contact", systemImage: "cross.case")
            }
        }
    }

    private func respond(to request: Partnership, accept: Bool) {
        Task {
            try? await Sync.shared.respond(to: request.partnerID, accept: accept)
            if accept {
                request.status = "accepted"
            } else {
                context.delete(request)
            }
            try? context.save()
        }
    }

    private func addDemoRequest() {
        guard let code = try? IdentityService.generatePublicID() else { return }
        let demoCount = partnerships.filter { $0.partnerName.hasPrefix(String(localized: "Demo partner")) }.count
        let name = demoCount == 0 ? String(localized: "Demo partner") : String(localized: "Demo partner \(demoCount + 1)")
        context.insert(Partnership(partnerID: code, partnerName: name, isIncoming: true))
        try? context.save()
    }
}

private struct EmergencyContactRow: View {
    let contact: EmergencyContact

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: contact.kind.symbol)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Self.color(for: contact.kind), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(contact.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(contact.value)
                    .font(.body.monospacedDigit())
            }
            Spacer()
            Image(systemName: "pencil")
                .foregroundStyle(.tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit emergency contact")
    }

    static func color(for kind: EmergencyContact.Kind) -> Color {
        switch kind {
        case .phone: .green
        case .zalo: .blue
        case .whatsApp: Color(red: 0.15, green: 0.68, blue: 0.38)
        case .telegram: .cyan
        }
    }
}

/// Adds or edits one emergency contact: which app, and the number or username.
private struct EmergencyContactEditor: View {
    @State var contact: EmergencyContact
    let isNew: Bool
    var onSave: (EmergencyContact) -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var valueFocused: Bool

    private var trimmed: String { contact.value.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact via") {
                    Picker("Contact via", selection: $contact.kind) {
                        ForEach(EmergencyContact.Kind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    TextField(placeholder, text: $contact.value)
                        .keyboardType(contact.kind == .telegram ? .asciiCapable : .phonePad)
                        .textContentType(contact.kind == .telegram ? .username : .telephoneNumber)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($valueFocused)
                } footer: {
                    Text(hint)
                }

                if !isNew {
                    Section {
                        Button("Delete contact", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New emergency contact" : "Emergency contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        contact.value = trimmed
                        onSave(contact)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { valueFocused = isNew }
        }
        .presentationDetents([.medium])
    }

    private var placeholder: String {
        contact.kind == .telegram ? "@username" : "+84 912 345 678"
    }

    private var hint: String {
        switch contact.kind {
        case .phone: String(localized: "Phone number, with country code if they may call from abroad.")
        case .zalo: String(localized: "The phone number registered with Zalo.")
        case .whatsApp: String(localized: "The phone number registered with WhatsApp, with country code.")
        case .telegram: String(localized: "Your Telegram username (like @linh) or phone number.")
        }
    }
}

private struct MyAvatarRow: View {
    @Bindable var user: LocalUser
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var confirmingRemovePhoto = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            AvatarView(name: user.displayName, id: user.id, imageData: user.avatarData, size: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(user.displayName)
                    .font(.title3.weight(.semibold))
                HStack(spacing: 16) {
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Text(user.avatarData == nil ? "Add photo" as LocalizedStringKey : "Change photo")
                    }
                    if user.avatarData != nil {
                        Button("Remove", role: .destructive) {
                            confirmingRemovePhoto = true
                        }
                    }
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
            }
            Spacer()
            Button {
                nameDraft = user.displayName
                editingName = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit name")
        }
        .padding(.vertical, 4)
        .confirmationDialog("Remove your photo?", isPresented: $confirmingRemovePhoto, titleVisibility: .visible) {
            Button("Remove photo", role: .destructive) {
                user.avatarData = nil
                try? user.modelContext?.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your avatar goes back to your initial.")
        }
        .alert("Your name", isPresented: $editingName) {
            TextField("Your name", text: $nameDraft)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
            Button("Save") {
                let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                user.displayName = trimmed
                try? user.modelContext?.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Partners see this name.")
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let avatar = AvatarView.avatarData(from: data) {
                    user.avatarData = avatar
                    try? user.modelContext?.save()
                }
                pickedPhoto = nil
            }
        }
    }
}

private struct RequestRow: View {
    let partnership: Partnership
    var onRespond: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PartnerTitle(partnership: partnership)
            Text("Wants to see your check-ins.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button("Decline", role: .destructive) { onRespond(false) }
                    .buttonStyle(.bordered)
                Button("Accept") { onRespond(true) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SentRow: View {
    let partnership: Partnership
    var onCancel: () -> Void

    var body: some View {
        HStack {
            PartnerTitle(partnership: partnership)
            Spacer()
            Text("Waiting")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Button("Cancel", role: .destructive, action: onCancel)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

private struct PartnerRow: View {
    @Bindable var partnership: Partnership
    @Query private var settings: [AppSettings]
    @State private var editingNickname = false
    @State private var nicknameDraft = ""
    @State private var confirmingShare = false

    /// Turning sharing on asks first; turning it off happens right away.
    private var shareBinding: Binding<Bool> {
        Binding {
            partnership.canSeeLocation
        } set: { on in
            if on {
                confirmingShare = true
            } else {
                partnership.canSeeLocation = false
                try? partnership.modelContext?.save()
            }
        }
    }

    private var shareMessage: String {
        let name = partnership.displayName
        var message = String(localized: "\(name) will see where you checked in and where you last used the app. You can turn this off anytime.")
        if settings.first?.shareLocation != true {
            message += "\n\n" + String(localized: "Location is off in Settings, so nothing is shared until you turn it on there.")
        }
        return message
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                PartnerTitle(partnership: partnership)
                Spacer()
                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                Button {
                    nicknameDraft = partnership.nickname ?? ""
                    editingNickname = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit nickname")
            }
            if partnership.isAccepted {
                Toggle("Share my location", isOn: shareBinding)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
        .alert("Share your location with \(partnership.displayName)?", isPresented: $confirmingShare) {
            Button("Share") {
                partnership.canSeeLocation = true
                try? partnership.modelContext?.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(shareMessage)
        }
        .alert("Nickname", isPresented: $editingNickname) {
            TextField(partnership.partnerName, text: $nicknameDraft)
                .textInputAutocapitalization(.words)
            Button("Save") { saveNickname(nicknameDraft) }
            if partnership.nickname != nil {
                Button("Remove nickname", role: .destructive) { saveNickname("") }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only you see this. Leave it empty to use \(partnership.partnerName).")
        }
    }

    private func saveNickname(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        partnership.nickname = trimmed.isEmpty ? nil : trimmed
        try? partnership.modelContext?.save()
    }

    private var statusLabel: String {
        switch partnership.status {
        case "accepted": String(localized: "Partner")
        case "declined": String(localized: "Declined")
        default: String(localized: "Invite sent")
        }
    }

    private var statusColor: Color {
        switch partnership.status {
        case "accepted": .green
        case "declined": .red
        default: .secondary
        }
    }
}

private struct PartnerTitle: View {
    let partnership: Partnership

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: partnership.displayName, id: partnership.partnerID)
            VStack(alignment: .leading, spacing: 2) {
                Text(partnership.displayName)
                    .font(.headline)
                Text(partnership.nickname == nil ? partnership.partnerID : "\(partnership.partnerName) · \(partnership.partnerID)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AddPartnerView: View {
    let ownCode: String
    let existingCodes: Set<String>
    /// A code from an invite link, filled in when the sheet opens.
    var initialCode = ""

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var name = ""
    @State private var sending = false
    @State private var scanning = false
    @FocusState private var codeFocused: Bool

    private var problem: String? {
        if code.isEmpty { return nil }
        if code.count < IdentityService.codeLength { return String(localized: "Codes have \(IdentityService.codeLength) characters.") }
        if code == ownCode { return String(localized: "That's your own code.") }
        if existingCodes.contains(code) { return String(localized: "You've already added this partner.") }
        return nil
    }

    private var canAdd: Bool { IdentityService.isValidCode(code) && problem == nil && !sending }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ABCD1234", text: $code)
                        .font(.title2.monospaced().weight(.semibold))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .textContentType(.oneTimeCode)
                        .focused($codeFocused)
                        .submitLabel(.next)
                        .onChange(of: code) { _, newValue in
                            let normalized = IdentityService.normalizeCode(newValue)
                            if normalized != newValue { code = normalized }
                        }
                    Button {
                        scanning = true
                    } label: {
                        Label("Scan QR code", systemImage: "qrcode.viewfinder")
                    }
                } header: {
                    Text("Their invite code")
                } footer: {
                    Text(problem ?? String(localized: "Ask your partner for the code on their Users tab. Spaces and dashes are ignored."))
                        .foregroundStyle(problem == nil ? Color.secondary : Color.red)
                }

                Section {
                    TextField("e.g. Mom", text: $name)
                        .textContentType(.name)
                        .submitLabel(.done)
                        .onSubmit { if canAdd { add() } }
                } header: {
                    Text("Nickname (optional)")
                } footer: {
                    Text("Only you see this. You can change it later on the Users tab.")
                }
            }
            .navigationTitle("Add partner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add).disabled(!canAdd)
                }
            }
            .onAppear {
                if code.isEmpty, !initialCode.isEmpty {
                    code = initialCode
                } else {
                    codeFocused = true
                }
            }
            .sheet(isPresented: $scanning) {
                ScanInviteView { scanned in code = scanned }
            }
        }
    }

    private func add() {
        sending = true
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let partnership = Partnership(partnerID: code, partnerName: "Partner \(code.prefix(4))")
        partnership.nickname = trimmed.isEmpty ? nil : trimmed
        context.insert(partnership)
        Task {
            try? await Sync.shared.sendInvite(to: partnership.partnerID)
            try? context.save()
            dismiss()
            // Mock partners accept after a moment; with a real backend the status arrives through sync.
            if Sync.shared is MockSyncService {
                try? await Task.sleep(for: .seconds(5))
                guard !partnership.isDeleted, partnership.status == "pending" else { return }
                partnership.status = "accepted"
                try? context.save()
            }
        }
    }
}
