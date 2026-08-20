//
//  LocationManager.swift
//  Comebackone day 1.2
//

import CoreLocation
import Combine
import UserNotifications

class LocationManager: NSObject, ObservableObject {
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// User opt-in for "you're near a wishlist place" notifications. Off by
    /// default — enabling it is what triggers the Always-location request.
    @Published var proximityNudgesEnabled: Bool {
        didSet {
            UserDefaults.standard.set(proximityNudgesEnabled, forKey: Self.nudgesEnabledKey)
            if proximityNudgesEnabled {
                updateMonitoredRegions(for: knownMemories)
            } else {
                for region in manager.monitoredRegions {
                    manager.stopMonitoring(for: region)
                }
            }
        }
    }

    private let manager = CLLocationManager()
    private var knownMemories: [TravelMemory] = []

    private static let nudgesEnabledKey = "ProximityNudgesEnabled"
    private static let lastNudgedKeyPrefix = "ProximityLastNudged."
    private static let maxMonitoredRegions = 20
    private static let nudgeRadius: CLLocationDistance = 150
    private static let nudgeCooldown: TimeInterval = 60 * 60 * 12

    override init() {
        proximityNudgesEnabled = UserDefaults.standard.bool(forKey: Self.nudgesEnabledKey)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// Requests notification permission, then upgrades to Always location access.
    /// The toggle only flips on once the user has been asked for both — if they
    /// decline notifications, monitoring never starts.
    func enableProximityNudges() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                self?.manager.requestAlwaysAuthorization()
                self?.proximityNudgesEnabled = true
            }
        }
    }

    func disableProximityNudges() {
        proximityNudgesEnabled = false
    }

    /// Re-registers monitored regions for the nearest wishlist places (iOS caps
    /// monitored regions at 20 per app). Call whenever the memory list changes.
    func updateMonitoredRegions(for memories: [TravelMemory]) {
        knownMemories = memories
        guard proximityNudgesEnabled else { return }

        let wishlist = memories.filter { $0.visitStatus == .wantToGo }
        let nearest: [TravelMemory]
        if let currentLocation {
            let origin = CLLocation(latitude: currentLocation.latitude, longitude: currentLocation.longitude)
            nearest = wishlist.sorted {
                origin.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                    < origin.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
            }
        } else {
            nearest = wishlist
        }
        let toMonitor = Array(nearest.prefix(Self.maxMonitoredRegions))

        let keepIDs = Set(toMonitor.map { $0.id.uuidString })
        for region in manager.monitoredRegions where !keepIDs.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }

        let alreadyMonitored = Set(manager.monitoredRegions.map(\.identifier))
        for memory in toMonitor where !alreadyMonitored.contains(memory.id.uuidString) {
            let region = CLCircularRegion(
                center: memory.coordinate,
                radius: Self.nudgeRadius,
                identifier: memory.id.uuidString
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
    }

    private func shouldNudge(for identifier: String) -> Bool {
        let key = Self.lastNudgedKeyPrefix + identifier
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
           Date().timeIntervalSince(last) < Self.nudgeCooldown {
            return false
        }
        return true
    }

    private func markNudged(for identifier: String) {
        UserDefaults.standard.set(Date(), forKey: Self.lastNudgedKeyPrefix + identifier)
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard proximityNudgesEnabled, shouldNudge(for: region.identifier) else { return }
        markNudged(for: region.identifier)

        let name = knownMemories.first(where: { $0.id.uuidString == region.identifier })?.name ?? "a saved place"
        let content = UNMutableNotificationContent()
        content.title = "You're near \(name)"
        content.body = "It's on your wishlist — want to come back one day?"
        content.sound = .default
        let request = UNNotificationRequest(identifier: region.identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
