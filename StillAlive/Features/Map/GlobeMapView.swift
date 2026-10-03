import MapKit
import SwiftData
import SwiftUI

/// Me and every accepted partner on a 3D globe, at our last known locations.
struct GlobeMapView: View {
    @Query private var users: [LocalUser]
    @Query private var settings: [AppSettings]
    @Query(sort: \Partnership.createdAt) private var partnerships: [Partnership]
    @State private var position: MapCameraPosition = .camera(Self.globeCamera(over: nil))
    @State private var partnerPins: [String: PersonPin] = [:]
    @State private var selectedID: String?
    @Namespace private var mapScope
    /// Our own 3D setting; the system pitch toggle flipped back and forth while flying to a person.
    @State private var is3D = true
    /// Where the camera settled last, so the 3D button can tilt the current view.
    @State private var lastCamera: MapCamera?
    /// Renamed from "mapType" so everyone starts on Satellite again.
    @AppStorage("mapTypeChoice") private var mapType = MapType.satellite

    private var partners: [Partnership] { partnerships.filter(\.isAccepted) }

    /// Camera tilt for the 3D view.
    private static let tilt: Double = 60

    /// Distance at which MapKit draws the whole Earth as a globe.
    private static let globeDistance: CLLocationDistance = 25_000_000

    var body: some View {
        let me = myPin
        let pins = ([me] + partners.map { partnerPins[$0.partnerID] }).compactMap { $0 }.filter { $0.coordinate != nil }

        Map(position: $position, selection: $selectedID, scope: mapScope) {
            ForEach(pins) { pin in
                if let coordinate = pin.coordinate {
                    Annotation(pin.name, coordinate: coordinate, anchor: .bottom) {
                        PinView(pin: pin, isSelected: selectedID == pin.id)
                    }
                    // The pin's own callout shows the name; MapKit's label under it would repeat it.
                    .annotationTitles(.hidden)
                    .tag(pin.id)
                }
            }
        }
        .mapStyle(mapType.style)
        // Built-in controls go in the button row below instead of their default spots.
        .mapControls {}
        .safeAreaInset(edge: .bottom) {
            peopleStrip(me: me)
        }
        .safeAreaInset(edge: .top, alignment: .trailing) {
            HStack(spacing: 10) {
                MapCompass(scope: mapScope)
                Button {
                    is3D.toggle()
                    guard let camera = lastCamera else { return }
                    withAnimation(.easeInOut(duration: 0.8)) {
                        position = .camera(MapCamera(centerCoordinate: camera.centerCoordinate, distance: camera.distance,
                                                     heading: camera.heading, pitch: is3D ? Self.tilt : 0))
                    }
                } label: {
                    Text("3D")
                        .font(.headline)
                        .foregroundStyle(is3D ? Color.accentColor : Color.secondary)
                        .frame(width: 48, height: 48)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel(is3D ? "3D on" : "3D off")
                Button {
                    selectedID = nil
                    withAnimation(.easeInOut(duration: 1.5)) {
                        position = .camera(Self.globeCamera(over: me?.coordinate ?? pins.first?.coordinate))
                    }
                } label: {
                    Image(systemName: "globe.asia.australia.fill")
                        .font(.title2)
                        .padding(10)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Show the whole globe")

                Menu {
                    Picker("Map type", selection: $mapType) {
                        ForEach(MapType.allCases) { type in
                            Label(type.title, systemImage: type.symbol).tag(type)
                        }
                    }
                } label: {
                    Image(systemName: "map.fill")
                        .font(.title2)
                        .padding(10)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Map type")
            }
            .padding(.trailing, 12)
            .padding(.top, 4)
        }
        .mapScope(mapScope)
        .onChange(of: selectedID) { _, id in
            guard let id, let coordinate = (pins.first { $0.id == id })?.coordinate else { return }
            withAnimation(.easeInOut(duration: 2)) {
                position = .camera(MapCamera(centerCoordinate: coordinate, distance: 4000, heading: 0, pitch: is3D ? Self.tilt : 0))
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            lastCamera = context.camera
        }
        .task(id: partners.map { "\($0.partnerID)|\($0.displayName)" }) {
            await loadPartnerPins()
        }
        .task {
            // Start over me once my location is known.
            if let coordinate = me?.coordinate {
                position = .camera(Self.globeCamera(over: coordinate))
            }
        }
    }

    private var myPin: PersonPin? {
        guard let user = users.first else { return nil }
        let coordinate = user.lastLatitude.flatMap { lat in user.lastLongitude.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } }
        let detail: String
        if coordinate == nil {
            detail = settings.first?.shareLocation == true ? "Location not found yet" : "Location is off"
        } else {
            detail = user.lastPlaceName ?? "Last location"
        }
        return PersonPin(id: user.id, name: "Me", avatarName: user.displayName, imageData: user.avatarData,
                         coordinate: coordinate, detail: detail, updatedAt: user.lastLocationAt)
    }

    @ViewBuilder
    private func peopleStrip(me: PersonPin?) -> some View {
        let people = ([me] + partners.map { partnerPins[$0.partnerID] ?? PersonPin.loading(for: $0) }).compactMap { $0 }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(people) { person in
                    Button {
                        if person.coordinate != nil { selectedID = person.id }
                    } label: {
                        HStack(spacing: 8) {
                            AvatarView(name: person.avatarName, id: person.id, imageData: person.imageData, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(person.name).font(.subheadline.weight(.semibold))
                                Text(person.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(selectedID == person.id ? Color.accentColor : .clear, lineWidth: 2))
                        .opacity(person.coordinate == nil ? 0.55 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(person.coordinate == nil)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func loadPartnerPins() async {
        var loaded: [String: PersonPin] = [:]
        for partner in partners {
            let shares = (try? await Sync.shared.partnerSharesLocation(partner.partnerID)) ?? false
            var latest: RemoteSlot?
            if shares {
                latest = ((try? await Sync.shared.pull(partnerID: partner.partnerID)) ?? [])
                    .filter { $0.latitude != nil && $0.longitude != nil }
                    .max { ($0.resolvedAt ?? $0.scheduledAt) < ($1.resolvedAt ?? $1.scheduledAt) }
            }
            let coordinate = latest.flatMap { slot in slot.latitude.flatMap { lat in slot.longitude.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } } }
            let detail = !shares ? "Not sharing" : coordinate == nil ? "No location yet" : (latest?.placeName ?? "Last check-in")
            loaded[partner.partnerID] = PersonPin(id: partner.partnerID, name: partner.displayName, avatarName: partner.displayName,
                                                 coordinate: coordinate, detail: detail, updatedAt: latest?.resolvedAt)
        }
        partnerPins = loaded
    }

    private static func globeCamera(over coordinate: CLLocationCoordinate2D?) -> MapCamera {
        MapCamera(centerCoordinate: coordinate ?? CLLocationCoordinate2D(latitude: 15, longitude: 105),
                  distance: globeDistance, heading: 0, pitch: 0)
    }
}

enum MapType: String, CaseIterable, Identifiable {
    case standard, satellite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .satellite: "Satellite"
        }
    }

    var symbol: String {
        switch self {
        case .standard: "map"
        case .satellite: "globe.americas.fill"
        }
    }

    /// Both with realistic elevation, so terrain is 3D and zooming out shows a globe.
    /// Satellite keeps road and place labels so pins have context.
    var style: MapStyle {
        switch self {
        case .standard: .standard(elevation: .realistic)
        case .satellite: .hybrid(elevation: .realistic)
        }
    }
}

struct PersonPin: Identifiable {
    var id: String
    var name: String
    var avatarName: String
    var imageData: Data?
    var coordinate: CLLocationCoordinate2D?
    var detail: String
    var updatedAt: Date?

    static func loading(for partner: Partnership) -> PersonPin {
        PersonPin(id: partner.partnerID, name: partner.displayName, avatarName: partner.displayName, detail: "Loading…")
    }
}

private struct PinView: View {
    let pin: PersonPin
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            AvatarView(name: pin.avatarName, id: pin.id, imageData: pin.imageData, size: isSelected ? 44 : 34)
                .padding(3)
                .background(Circle().fill(.white))
                .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : .white, lineWidth: 2))
                .shadow(radius: 3)
            Image(systemName: "triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(180))
                .offset(y: -4)
            if isSelected {
                VStack(spacing: 0) {
                    Text(pin.name).font(.caption.weight(.semibold))
                    if let updatedAt = pin.updatedAt {
                        Text(updatedAt.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .animation(.spring, value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pin.name)
    }
}
