import MapKit
import SwiftUI

/// Where I last used the app, below the calendar on my own view.
struct LastLocationView: View {
    let user: LocalUser
    let sharingOn: Bool

    @Environment(\.modelContext) private var context
    @State private var locating = true

    var body: some View {
        LocationCard(
            coordinate: coordinate,
            placeName: user.lastPlaceName,
            updatedAt: user.lastLocationAt,
            emptyText: sharingOn ? (locating ? nil : String(localized: "Couldn't get your location.")) : nil,
            footnote: sharingOn ? nil : coordinate == nil
                ? String(localized: "Turn on location in Settings to save where you last used the app.")
                : String(localized: "Location is off, so this isn't updated. Turn it on in Settings."),
            showsPlaceholder: sharingOn
        )
        // Refresh whenever the card appears with sharing on, so turning it on shows a pin right away.
        .task(id: sharingOn) {
            guard sharingOn else { return }
            locating = true
            await CheckInService(context: context).recordLastLocation()
            locating = false
        }
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = user.lastLatitude, let lon = user.lastLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// A partner's location from their latest check-in that carried one.
struct PartnerLocationView: View {
    let name: String
    let sharesLocation: Bool
    let slots: [DisplaySlot]

    @State private var placeName: String?

    private var latest: DisplaySlot? {
        guard sharesLocation else { return nil }
        return slots
            .filter { $0.latitude != nil && $0.longitude != nil }
            .max { ($0.resolvedAt ?? $0.scheduledAt) < ($1.resolvedAt ?? $1.scheduledAt) }
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = latest?.latitude, let lon = latest?.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        LocationCard(
            coordinate: coordinate,
            placeName: placeName,
            updatedAt: latest?.resolvedAt,
            emptyText: nil,
            footnote: !sharesLocation ? String(localized: "\(name) doesn't want to share their location.")
                : coordinate == nil ? String(localized: "\(name) hasn't checked in with a location yet.") : nil,
            showsPlaceholder: false
        )
        .task(id: latest?.id) {
            placeName = nil
            guard let coordinate else { return }
            placeName = await LocationService.shared.placeName(for: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
    }
}

private struct LocationCard: View {
    let coordinate: CLLocationCoordinate2D?
    let placeName: String?
    let updatedAt: Date?
    /// Shown in the placeholder when there's no coordinate; nil shows a spinner.
    let emptyText: String?
    let footnote: String?
    let showsPlaceholder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Last location", systemImage: "location.fill")
                    .font(.headline)
                Spacer()
                if let coordinate {
                    Button {
                        openInMaps(coordinate)
                    } label: {
                        Label("Open in Maps", systemImage: "arrow.up.forward.app")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)),
                    interactionModes: []) {
                    Marker(placeName ?? "Here", coordinate: coordinate)
                }
                .id("\(coordinate.latitude),\(coordinate.longitude)")
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture { openInMaps(coordinate) }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(placeName ?? String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
                        .font(.subheadline.weight(.semibold))
                    if let updatedAt {
                        Text("Updated \(updatedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if showsPlaceholder {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 150)
                    .overlay {
                        if let emptyText {
                            Text(emptyText).foregroundStyle(.secondary)
                        } else {
                            ProgressView("Finding your location…")
                        }
                    }
            }

            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    /// Opens Apple Maps with a pin at `coordinate`, labelled with the place name.
    private func openInMaps(_ coordinate: CLLocationCoordinate2D) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = placeName ?? String(localized: "Last location")
        item.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)),
        ])
    }
}
