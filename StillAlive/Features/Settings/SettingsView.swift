import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query private var settings: [AppSettings]
    @Query private var users: [LocalUser]

    var body: some View {
        NavigationStack {
            if let settings = settings.first, let user = users.first {
                SettingsForm(settings: settings, user: user)
                    .navigationTitle("Settings")
            }
        }
    }
}

private struct SettingsForm: View {
    @Bindable var settings: AppSettings
    @Bindable var user: LocalUser
    @Environment(\.modelContext) private var context
    @State private var locationDenied = false
    @State private var showingPremium = false
    @State private var confirmingLogOut = false
    @Environment(AccountStore.self) private var accounts
    @Environment(\.openURL) private var openURL

    /// The language the app is showing, named in that language (e.g. "Tiếng Việt").
    static var currentLanguageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale(identifier: code).localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
    }

    private static let maxSlots = PlanLimits.checkInTimes

    var body: some View {
        Form {
            Section {
                ForEach(settings.slotTimes.indices, id: \.self) { index in
                    DatePicker("Check-in \(index + 1)", selection: timeBinding(at: index), displayedComponents: .hourAndMinute)
                }
                .onDelete { settings.slotTimes.remove(atOffsets: $0) }
                .deleteDisabled(settings.slotTimes.count <= 1)

                if settings.slotTimes.count < Self.maxSlots {
                    Button("Add check-in time", systemImage: "plus") {
                        settings.slotTimes.append(min((settings.slotTimes.max() ?? 540) + 60, SlotPlanner.minutesPerDay - 1))
                    }
                } else {
                    UpgradeRow(detail: "for more check-in times") { showingPremium = true }
                }
            } header: {
                Text("Check-in times")
            } footer: {
                Text("Changes apply today, except times earlier than a check-in you've already finished today; those start tomorrow.")
            }

            Section("Grace & reminders") {
                Stepper("Grace window: \(settings.graceMinutes) min", value: $settings.graceMinutes, in: 15...180, step: 15)
                Picker("Remind every", selection: $settings.remindEveryMinutes) {
                    ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
                }
            }

            Section("Puzzle difficulty") {
                Picker("Difficulty", selection: $settings.difficulty) {
                    Text("Easy").tag(1)
                    Text("Medium").tag(2)
                    Text("Hard").tag(3)
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle("Attach location to check-ins", isOn: locationBinding)
            } header: {
                Text("Location")
            } footer: {
                Text(locationDenied
                     ? "Location access is off for Still Here. You can allow it in the iOS Settings app."
                     : "Off by default. Only partners you choose will be able to see it.")
            }

            Section("Time zone") {
                NavigationLink {
                    TimeZonePicker(selection: $user.timeZoneID)
                } label: {
                    LabeledContent("Time zone", value: user.timeZoneID)
                }
            }

            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    LabeledContent {
                        HStack(spacing: 4) {
                            Text(Self.currentLanguageName)
                            Image(systemName: "arrow.up.forward.app")
                        }
                    } label: {
                        Label("Language", systemImage: "globe")
                    }
                }
                .foregroundStyle(.primary)
            } footer: {
                Text("Opens Still Here in the Settings app. Tap Language there to switch between English and Tiếng Việt.")
            }

            Section {
                NavigationLink("Auto-open with Shortcuts") { ShortcutsGuideView() }
            }

            Section {
                NavigationLink {
                    FAQView()
                } label: {
                    Label("FAQ", systemImage: "questionmark.circle")
                }
            }

            Section {
                Button("Log out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    confirmingLogOut = true
                }
                .foregroundStyle(.red)
                .confirmationDialog("Log out of Still Here?", isPresented: $confirmingLogOut, titleVisibility: .visible) {
                    Button("Log out", role: .destructive) {
                        Task {
                            await CheckInService(context: context).cancelAlerts()
                            accounts.logOut()
                        }
                    }
                } message: {
                    Text("Your data stays on this iPhone. Check-in alarms and reminders stop until you log in again. You can then log in to this or another account.")
                }
            }
        }
        .premiumComingSoon(isPresented: $showingPremium,
                           message: "You've reached the free plan's check-in time limit. Premium will let you add more. You can still change the time you have.")
        .onChange(of: scheduleSignature) {
            Task { await CheckInService(context: context).refresh() }
        }
        .onDisappear {
            settings.slotTimes = SlotPlanner.normalized(settings.slotTimes)
        }
    }

    /// Anything that changes which slots exist or when reminders fire.
    private var scheduleSignature: String {
        "\(SlotPlanner.normalized(settings.slotTimes))|\(settings.graceMinutes)|\(settings.remindEveryMinutes)|\(user.timeZoneID)"
    }

    private func timeBinding(at index: Int) -> Binding<Date> {
        Binding {
            let minutes = settings.slotTimes.indices.contains(index) ? settings.slotTimes[index] : 0
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            guard settings.slotTimes.indices.contains(index) else { return }
            settings.slotTimes[index] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private var locationBinding: Binding<Bool> {
        Binding {
            settings.shareLocation
        } set: { enabled in
            guard enabled else {
                settings.shareLocation = false
                return
            }
            Task {
                let granted = await LocationService.shared.requestPermission()
                settings.shareLocation = granted
                locationDenied = !granted
            }
        }
    }
}

private struct TimeZonePicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var results: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        return search.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            Button("Use device time zone (\(TimeZone.current.identifier))") {
                selection = TimeZone.current.identifier
                dismiss()
            }
            ForEach(results, id: \.self) { identifier in
                Button {
                    selection = identifier
                    dismiss()
                } label: {
                    HStack {
                        Text(identifier).foregroundStyle(Color.primary)
                        Spacer()
                        if identifier == selection { Image(systemName: "checkmark") }
                    }
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle("Time zone")
    }
}

struct ShortcutsGuideView: View {
    var body: some View {
        List {
            Section {
                Text("iOS doesn't let apps open themselves. A personal Shortcuts automation can open Still Here at each check-in time so the puzzle is waiting for you.")
            }
            Section("Set it up") {
                Label("Open the Shortcuts app and go to Automation.", systemImage: "1.circle")
                Label("Tap New Automation → Time of Day, pick your first check-in time, Daily.", systemImage: "2.circle")
                Label("Choose Run Immediately.", systemImage: "3.circle")
                Label("Add the action Open Check-in (search for Still Here).", systemImage: "4.circle")
                Label("Repeat for each check-in time.", systemImage: "5.circle")
            }
            Section {
                Label("Say \"Check in with Still Here\" to Siri, or find Open Check-in in Spotlight.", systemImage: "mic")
            } header: {
                Text("Siri")
            }
        }
        .navigationTitle("Auto-open")
    }
}
