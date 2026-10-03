import CoreLocation
import SwiftData
import SwiftUI

struct MainView: View {
    @Query private var users: [LocalUser]
    @Query(sort: \CheckInSlot.scheduledAt) private var allSlots: [CheckInSlot]
    @Query(sort: \Partnership.createdAt) private var partnerships: [Partnership]
    @Query private var settings: [AppSettings]
    @State private var month = Date.now
    @State private var selectedDay: SlotDay?
    /// nil = me; otherwise an accepted partner's ID.
    @State private var selectedPartnerID: String?
    @State private var partnerSlots: [DisplaySlot] = []
    @State private var partnerSharesLocation = false
    /// Every accepted partner's days, shown under the dates on my calendar.
    @State private var calendarPartners: [CalendarPartner] = []
    @AppStorage("showPartnersOnCalendar") private var showPartners = true

    /// Partners drawn on my calendar and listed in day details.
    private var visibleCalendarPartners: [CalendarPartner] {
        selectedPartnerID == nil && showPartners ? calendarPartners : []
    }

    private var partners: [Partnership] { partnerships.filter(\.isAccepted) }

    var body: some View {
        NavigationStack {
            if let user = users.first {
                let slots = selectedPartnerID == nil
                    ? allSlots.filter { $0.ownerID == user.id }.map(DisplaySlot.init)
                    : partnerSlots
                let byDay = Dictionary(grouping: slots, by: \.key.dayKey)
                ScrollView {
                    VStack(spacing: 20) {
                        if !partners.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    PersonChip(name: "Me", avatarName: user.displayName, id: user.id, imageData: user.avatarData,
                                               isSelected: selectedPartnerID == nil) { selectedPartnerID = nil }
                                    ForEach(partners) { partner in
                                        PersonChip(name: partner.displayName, avatarName: partner.displayName, id: partner.partnerID,
                                                   isSelected: selectedPartnerID == partner.partnerID) { selectedPartnerID = partner.partnerID }
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                            }
                        }
                        MetricsView(metrics: MetricsCalculator.compute(
                            slots.map(\.snapshot),
                            todayKey: DayKey.string(for: .now, in: user.timeZone)
                        ))
                        if selectedPartnerID == nil, !partners.isEmpty {
                            Toggle(isOn: $showPartners) {
                                Label("Show partners", systemImage: "person.2")
                            }
                            .padding(.horizontal, 4)
                        }
                        CalendarView(month: $month, timeZone: user.timeZone, slotsByDay: byDay,
                                     partners: visibleCalendarPartners) { dayKey in
                            selectedDay = SlotDay(dayKey: dayKey)
                        }
                        if let partner = selectedPartner {
                            PartnerLocationView(name: partner.displayName, sharesLocation: partnerSharesLocation, slots: partnerSlots)
                        } else {
                            LastLocationView(user: user, sharingOn: settings.first?.shareLocation ?? false)
                        }
                    }
                    .padding()
                }
                .navigationTitle(selectedPartner?.displayName ?? "StillAlive?")
                .sheet(item: $selectedDay) { day in
                    DayDetailView(dayKey: day.dayKey, slots: byDay[day.dayKey] ?? [], timeZone: user.timeZone,
                                  partners: visibleCalendarPartners.compactMap { partner in
                                      partner.slotsByDay[day.dayKey].map { DayDetailView.PartnerSlots(id: partner.id, name: partner.name, slots: $0) }
                                  })
                        .presentationDetents([.medium, .large])
                }
                .task(id: selectedPartnerID) {
                    await loadPartnerSlots()
                }
                .task(id: partners.map { "\($0.partnerID)|\($0.displayName)" }) {
                    await loadCalendarPartners()
                }
                .onChange(of: partners.map(\.partnerID)) { _, ids in
                    // The selected partner was removed.
                    if let selected = selectedPartnerID, !ids.contains(selected) {
                        selectedPartnerID = nil
                    }
                }
            }
        }
    }

    private var selectedPartner: Partnership? {
        partners.first { $0.partnerID == selectedPartnerID }
    }

    private func loadCalendarPartners() async {
        var loaded: [CalendarPartner] = []
        for partner in partners {
            let remote = (try? await Sync.shared.pull(partnerID: partner.partnerID)) ?? []
            let byDay = Dictionary(grouping: remote.map(DisplaySlot.init), by: \.key.dayKey)
                .mapValues { $0.sorted { $0.scheduledAt < $1.scheduledAt } }
            loaded.append(CalendarPartner(id: partner.partnerID, name: partner.displayName, slotsByDay: byDay))
        }
        calendarPartners = loaded
    }

    private func loadPartnerSlots() async {
        guard let partnerID = selectedPartnerID else {
            partnerSlots = []
            return
        }
        let remote = (try? await Sync.shared.pull(partnerID: partnerID)) ?? []
        partnerSharesLocation = (try? await Sync.shared.partnerSharesLocation(partnerID)) ?? false
        partnerSlots = remote.map(DisplaySlot.init)
    }
}

/// One person in the selector at the top of Main.
private struct PersonChip: View {
    let name: String
    let avatarName: String
    let id: String
    var imageData: Data?
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                AvatarView(name: avatarName, id: id, imageData: imageData, size: 52)
                    .padding(3)
                    .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5))
                Text(name)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 72)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A slot shown on Main, from my store or from a partner's synced data.
struct DisplaySlot: Identifiable, Equatable {
    var key: SlotKey
    var scheduledAt: Date
    var state: SlotState
    var resolvedAt: Date?
    var latitude: Double?
    var longitude: Double?
    var placeName: String?

    var id: String { key.id }
    var snapshot: SlotSnapshot { SlotSnapshot(key: key, scheduledAt: scheduledAt, state: state) }

    init(_ slot: CheckInSlot) {
        self.init(key: slot.key, scheduledAt: slot.scheduledAt, state: slot.state,
                  resolvedAt: slot.resolvedAt, latitude: slot.latitude, longitude: slot.longitude, placeName: slot.placeName)
    }

    init(_ slot: RemoteSlot) {
        self.init(key: SlotKey(dayKey: slot.dayKey, slotIndex: slot.slotIndex), scheduledAt: slot.scheduledAt, state: slot.state,
                  resolvedAt: slot.resolvedAt, latitude: slot.latitude, longitude: slot.longitude, placeName: slot.placeName)
    }

    init(key: SlotKey, scheduledAt: Date, state: SlotState, resolvedAt: Date?, latitude: Double?, longitude: Double?, placeName: String?) {
        self.key = key
        self.scheduledAt = scheduledAt
        self.state = state
        self.resolvedAt = resolvedAt
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
    }
}

private struct SlotDay: Identifiable {
    var dayKey: String
    var id: String { dayKey }
}

struct DayDetailView: View {
    struct PartnerSlots: Identifiable {
        var id: String
        var name: String
        var slots: [DisplaySlot]
    }

    let dayKey: String
    let slots: [DisplaySlot]
    let timeZone: TimeZone
    var partners: [PartnerSlots] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if slots.isEmpty {
                        Text("No check-ins scheduled this day.")
                            .foregroundStyle(.secondary)
                    }
                    slotRows(slots)
                } header: {
                    if !partners.isEmpty { Text("Me") }
                }
                ForEach(partners) { partner in
                    Section {
                        slotRows(partner.slots)
                    } header: {
                        HStack(spacing: 8) {
                            AvatarView(name: partner.name, id: partner.id, size: 20)
                                .frame(width: 26, height: 26)
                                .background { DayProgressRing(states: partner.slots.map(\.state), lineWidth: 2, gap: 1) }
                            Text(partner.name)
                        }
                        .textCase(nil)
                    }
                }
            }
            .navigationTitle(DayKey.display(dayKey))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func slotRows(_ slots: [DisplaySlot]) -> some View {
        ForEach(slots.sorted { $0.scheduledAt < $1.scheduledAt }) { slot in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SlotMarker(state: slot.state, size: 12)
                    Text(slot.scheduledAt.formatted(time))
                        .font(.headline)
                    Spacer()
                    Text(slot.state.label)
                        .foregroundStyle(.secondary)
                }
                if let resolvedAt = slot.resolvedAt, slot.state != .missed {
                    Text("At \(resolvedAt.formatted(time))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if slot.latitude != nil || slot.placeName != nil {
                    SlotPlaceLabel(slot: slot)
                }
            }
        }
    }

    private var time: Date.FormatStyle {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return style
    }
}

/// The slot's saved address; older check-ins without one are looked up when shown.
private struct SlotPlaceLabel: View {
    let slot: DisplaySlot
    @State private var lookedUp: String?
    @State private var lookupFailed = false

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.placeName ?? lookedUp ?? (lookupFailed ? "Unknown place" : "Finding address…"))
                if let lat = slot.latitude, let lon = slot.longitude {
                    Text(String(format: "%.5f, %.5f", lat, lon))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
        } icon: {
            Image(systemName: "location")
        }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .task(id: slot.id) {
                guard slot.placeName == nil, let lat = slot.latitude, let lon = slot.longitude else { return }
                lookedUp = await LocationService.shared.placeName(for: CLLocation(latitude: lat, longitude: lon))
                lookupFailed = lookedUp == nil
            }
    }
}

extension SlotState {
    var label: String {
        switch self {
        case .pending: "Pending"
        case .checkedIn: "Checked in"
        case .skipped: "Skipped"
        case .missed: "Missed"
        }
    }
}
