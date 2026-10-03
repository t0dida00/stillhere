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
    @State private var showingPremium = false

    private var canAddPartner: Bool { PlanLimits.canAddPartner(partnerships) }
    @State private var editingContacts = false

    private var received: [Partnership] { partnerships.filter { $0.isIncoming && $0.status == "pending" } }
    private var sent: [Partnership] { partnerships.filter { !$0.isIncoming && $0.status == "pending" } }
    private var partners: [Partnership] { partnerships.filter { $0.status != "pending" } }

    var body: some View {
        NavigationStack {
            List {
                if let user = users.first {
                    meSection(user)
                    emergencySection(user)
                }

                Section {
                    if received.isEmpty {
                        Text("No invitations right now.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(received) { request in
                        RequestRow(partnership: request, canAccept: canAddPartner,
                                   onUpgrade: { showingPremium = true }) { accept in respond(to: request, accept: accept) }
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
                    if canAddPartner {
                        Button {
                            addingPartner = true
                        } label: {
                            Label("Add partner by code", systemImage: "person.badge.plus")
                        }
                    } else {
                        UpgradeButton { showingPremium = true }
                    }
                } header: {
                    Text("Partners \(PlanLimits.partnerSlotsUsed(partnerships))/\(PlanLimits.partners)")
                } footer: {
                    Text("Until sync is available, partners are simulated: invites are accepted after a few seconds and check-ins are made up.")
                }
            }
            .navigationTitle("Users")
            .sheet(isPresented: $addingPartner, onDismiss: { linkedCode = "" }) {
                AddPartnerView(ownCode: users.first?.id ?? "", existingCodes: Set(partnerships.map(\.partnerID)), initialCode: linkedCode)
            }
            // On the List, not inside a section: a sheet attached to a section closes when the list redraws.
            .sheet(isPresented: $editingContacts) {
                if let user = users.first {
                    EmergencyContactsEditor(contacts: user.emergencyContacts) { saved in
                        user.emergencyContacts = saved
                        try? context.save()
                    }
                }
            }
            .sheet(isPresented: $showingQR) {
                if let user = users.first {
                    InviteQRView(name: user.displayName, code: user.id)
                }
            }
            .onChange(of: router.pendingInviteCode, initial: true) { _, code in
                guard let code else { return }
                router.pendingInviteCode = nil
                guard canAddPartner else {
                    showingPremium = true
                    return
                }
                linkedCode = code
                addingPartner = true
            }
            .alert("Premium is coming soon", isPresented: $showingPremium) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The free plan has up to \(PlanLimits.partners) partners, counting invites you've sent. Premium will let you add more. For now, remove a partner or cancel a sent invite to make room.")
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
        } header: {
            Text("Me")
        } footer: {
            Text("Partners use this code to request to see your check-ins.")
        }
    }

    private func emergencySection(_ user: LocalUser) -> some View {
        Section {
            emergencyContactRows(user)
        } header: {
            Text("Emergency contacts")
        } footer: {
            Text("Up to \(EmergencyContact.maxCount) ways for partners to reach you if you miss check-ins.")
        }
    }

    @ViewBuilder
    private func emergencyContactRows(_ user: LocalUser) -> some View {
        let contacts = user.emergencyContacts
        ForEach(contacts) { contact in
            Button {
                editingContacts = true
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
        Button {
            editingContacts = true
        } label: {
            Label(contacts.isEmpty ? "Add emergency contacts" : "Edit emergency contacts", systemImage: "cross.case")
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
            ContactAppIcon(kind: contact.kind)
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
        .accessibilityHint("Edit emergency contacts")
    }
}

/// App badge in each app's brand color: green phone, blue Zalo wordmark, green WhatsApp
/// chat bubble, blue Telegram paper plane.
struct ContactAppIcon: View {
    let kind: EmergencyContact.Kind
    var size: CGFloat = 32

    var body: some View {
        Group {
            switch kind {
            case .phone:
                RoundedRectangle(cornerRadius: size * 0.24)
                    .fill(Color(red: 0.20, green: 0.78, blue: 0.35))
                    .overlay { symbol("phone.fill", scale: 0.5) }
            case .zalo:
                RoundedRectangle(cornerRadius: size * 0.24)
                    .fill(Color(red: 0.0, green: 0.41, blue: 1.0))
                    .overlay {
                        Text(verbatim: "Zalo")
                            .font(.system(size: size * 0.3, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    }
            case .whatsApp:
                Circle()
                    .fill(Color(red: 0.15, green: 0.83, blue: 0.40))
                    .overlay { symbol("phone.bubble.fill", scale: 0.5) }
            case .telegram:
                Circle()
                    .fill(Color(red: 0.13, green: 0.62, blue: 0.85))
                    .overlay { symbol("paperplane.fill", scale: 0.46).offset(x: -size * 0.03, y: size * 0.02) }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func symbol(_ name: String, scale: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size * scale, weight: .semibold))
            .foregroundStyle(.white)
    }
}

/// Edits all emergency contacts at once: up to `EmergencyContact.maxCount`, any mix of apps
/// (3 phones, 2 phones and a Zalo, ...). Each row has its own app, field and hint.
private struct EmergencyContactsEditor: View {
    let contacts: [EmergencyContact]
    var onSave: ([EmergencyContact]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [EmergencyContact] = []
    @FocusState private var focused: UUID?

    private var canSave: Bool {
        rows.allSatisfy { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($rows) { $row in
                        ContactEditRow(contact: $row, focused: $focused) {
                            rows.removeAll { $0.id == row.id }
                        }
                    }
                    .onDelete { rows.remove(atOffsets: $0) }

                    if rows.count < EmergencyContact.maxCount {
                        Menu {
                            ForEach(EmergencyContact.Kind.allCases) { kind in
                                Button {
                                    add(kind)
                                } label: {
                                    Label(kind.title, systemImage: kind.symbol)
                                }
                            }
                        } label: {
                            Label("Add contact", systemImage: "plus.circle.fill")
                        }
                    }
                } header: {
                    Text("\(rows.count) of \(EmergencyContact.maxCount)")
                } footer: {
                    Text("Any mix of apps, for example 3 phone numbers, or 2 phones and a Zalo. Tap an app icon to change it.")
                }
            }
            .navigationTitle("Emergency contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .onAppear {
                rows = contacts
                if rows.isEmpty { add(.phone) }
            }
        }
    }

    private func add(_ kind: EmergencyContact.Kind) {
        guard rows.count < EmergencyContact.maxCount else { return }
        let contact = EmergencyContact(kind: kind, value: "")
        rows.append(contact)
        focused = contact.id
    }

    private func save() {
        onSave(rows.map { row in
            var contact = row
            contact.value = row.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return contact
        })
        dismiss()
    }
}

/// One contact in the editor: app (tap the icon to change), field and hint.
private struct ContactEditRow: View {
    @Binding var contact: EmergencyContact
    var focused: FocusState<UUID?>.Binding
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Menu {
                    Picker("App", selection: $contact.kind) {
                        ForEach(EmergencyContact.Kind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        ContactAppIcon(kind: contact.kind, size: 36)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel(Text("App: \(contact.kind.title)"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(contact.kind == .telegram ? "@username" : "+84 912 345 678", text: $contact.value)
                        .keyboardType(contact.kind == .telegram ? .asciiCapable : .phonePad)
                        .textContentType(contact.kind == .telegram ? .username : .telephoneNumber)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospacedDigit())
                        .focused(focused, equals: contact.id)
                }

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove")
            }
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
    /// False at the free plan's partner limit: the request stays, but accepting needs Premium.
    var canAccept = true
    var onUpgrade: () -> Void = {}
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
                if canAccept {
                    Button("Accept") { onRespond(true) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(action: onUpgrade) {
                        Text("Upgrade to Premium")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
            if !canAccept {
                Text("You have \(PlanLimits.partners) partners, the most on the free plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Shown where adding a partner would go over the free plan's limit.
private struct UpgradeButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text("Upgrade to Premium")
                    .foregroundStyle(.orange)
                Spacer()
                Text("for more partners")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
