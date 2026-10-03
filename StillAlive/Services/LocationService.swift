import CoreLocation

/// Opt-in, one-shot location. Never asks for permission until the user turns location on.
@MainActor
final class LocationService: NSObject {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var authWaiters: [CheckedContinuation<Bool, Never>] = []
    private var locationWaiters: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
    }

    func requestPermission() async -> Bool {
        guard manager.authorizationStatus == .notDetermined else { return isAuthorized }
        return await withCheckedContinuation { continuation in
            authWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation() async -> CLLocation? {
        guard isAuthorized else { return nil }
        return await withCheckedContinuation { continuation in
            locationWaiters.append(continuation)
            manager.requestLocation()
        }
    }

    /// A short place name such as "District 1, Ho Chi Minh City", or nil when offline.
    func placeName(for location: CLLocation) async -> String? {
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let parts = [placemark.subLocality ?? placemark.name, placemark.locality ?? placemark.administrativeArea]
        let name = parts.compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return name.isEmpty ? nil : name.joined(separator: ", ")
    }

    private func finishAuthorization() {
        guard manager.authorizationStatus != .notDetermined else { return }
        let waiters = authWaiters
        authWaiters = []
        waiters.forEach { $0.resume(returning: isAuthorized) }
    }

    private func finishLocation(_ location: CLLocation?) {
        let waiters = locationWaiters
        locationWaiters = []
        waiters.forEach { $0.resume(returning: location) }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.finishAuthorization() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.finishLocation(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finishLocation(nil) }
    }
}
