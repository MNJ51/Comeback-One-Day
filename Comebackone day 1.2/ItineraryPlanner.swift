//
//  ItineraryPlanner.swift
//  Comebackone day 1.2
//
//  Itinerary generation searches real nearby places live via MapKit
//  (MKLocalPointsOfInterestRequest — the same free, no-API-key system that
//  already powers "Use a Photo's Location" in AddMemoryView) rather than the
//  user's saved places. Apple's public MapKit API doesn't expose star ratings
//  for arbitrary businesses, so there's no rating data to filter live results
//  on — that's a real platform limitation, not an oversight.
//

import CoreLocation
import MapKit

enum ItineraryVibe: String, CaseIterable, Identifiable {
    case relaxed = "Relaxed"
    case adventure = "Adventure"
    case foodie = "Foodie"
    case culture = "Culture"
    /// Deliberately searches an unusual category pool (go-karts, planetariums,
    /// distilleries...) instead of the vibe's usual categories, so the plan
    /// surfaces things that wouldn't normally make an itinerary.
    case mystery = "Mystery"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .relaxed: return "cup.and.saucer.fill"
        case .adventure: return "figure.hiking"
        case .foodie: return "fork.knife"
        case .culture: return "building.columns.fill"
        case .mystery: return "questionmark.diamond.fill"
        }
    }

    /// The MapKit categories searched for this vibe. Every case here is a
    /// confirmed MKPointOfInterestCategory member available on iOS 18.
    var mapKitCategories: [MKPointOfInterestCategory] {
        switch self {
        case .relaxed:
            return [.cafe, .park, .beach, .spa, .winery, .nightlife]
        case .adventure:
            return [.park, .nationalPark, .hiking, .campground, .marina, .beach, .kayaking, .surfing, .rockClimbing]
        case .foodie:
            return [.restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket, .distillery]
        case .culture:
            return [.museum, .theater, .movieTheater, .landmark, .nationalMonument, .castle, .fortress, .planetarium, .musicVenue]
        case .mystery:
            return ItineraryPlanner.mysteryCategoryPool
        }
    }
}

enum ItineraryTravelMode: String, CaseIterable, Identifiable {
    case walking = "Walking"
    case driving = "Driving"
    case transit = "Public Transport"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .walking: return "figure.walk"
        case .driving: return "car.fill"
        case .transit: return "bus.fill"
        }
    }

    /// The MapKit directions mode this maps to when opening Apple Maps.
    var launchDirectionsModeKey: String {
        switch self {
        case .walking: return MKLaunchOptionsDirectionsModeWalking
        case .driving: return MKLaunchOptionsDirectionsModeDriving
        case .transit: return MKLaunchOptionsDirectionsModeTransit
        }
    }
}

/// A place found via live MapKit search — not a saved TravelMemory, so it has
/// no rating, notes, or photos, only what MapKit's business listing provides.
struct DiscoveredPlace: Identifiable {
    let id = UUID()
    let name: String
    let category: Category
    let coordinate: CLLocationCoordinate2D
    let address: String?
    let phoneNumber: String?
    let website: String?
}

struct ItineraryStop: Identifiable {
    let place: DiscoveredPlace
    let isMysteryStop: Bool
    var id: UUID { place.id }
}

enum ItineraryPlanner {
    /// Offbeat categories used both for Mystery-vibe's main search and as the
    /// bonus Mystery Stop pool for every other vibe.
    static let mysteryCategoryPool: [MKPointOfInterestCategory] = [
        .zoo, .aquarium, .planetarium, .distillery, .goKart, .miniGolf,
        .skatePark, .fairground, .rockClimbing, .kayaking, .surfing
    ]

    /// Searches real nearby places live via MapKit and builds a day out of the
    /// nearest matches for the vibe, plus (for non-Mystery vibes) one bonus
    /// stop from the offbeat Mystery pool, revealed only when tapped.
    static func discover(
        vibe: ItineraryVibe,
        origin: CLLocationCoordinate2D,
        maxDistanceKm: Double,
        stopCount: Int = 4
    ) async -> [ItineraryStop] {
        guard stopCount > 0 else { return [] }
        let radiusMeters = min(maxDistanceKm * 1000, 50_000)
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)

        let mainResults = await search(categories: vibe.mapKitCategories, center: origin, radius: radiusMeters)
        var seenNames = Set<String>()
        let ranked = mainResults
            .sorted { originLocation.distance(from: $0.clLocation) < originLocation.distance(from: $1.clLocation) }
            .filter { seenNames.insert($0.name.lowercased()).inserted }
        let picks = Array(ranked.prefix(stopCount))

        var stops = picks.map { ItineraryStop(place: $0, isMysteryStop: false) }

        if vibe != .mystery {
            let mysteryResults = await search(categories: mysteryCategoryPool, center: origin, radius: radiusMeters)
            let usedNames = Set(picks.map { $0.name.lowercased() })
            if let mystery = mysteryResults
                .sorted(by: { originLocation.distance(from: $0.clLocation) < originLocation.distance(from: $1.clLocation) })
                .first(where: { !usedNames.contains($0.name.lowercased()) }) {
                stops.append(ItineraryStop(place: mystery, isMysteryStop: true))
            }
        }

        return stops
    }

    private static func search(
        categories: [MKPointOfInterestCategory],
        center: CLLocationCoordinate2D,
        radius: CLLocationDistance
    ) async -> [DiscoveredPlace] {
        let request = MKLocalPointsOfInterestRequest(center: center, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start() else { return [] }
        return response.mapItems.compactMap { item in
            guard let name = item.name else { return nil }
            return DiscoveredPlace(
                name: name,
                category: Category.from(mapKitCategory: item.pointOfInterestCategory),
                coordinate: item.placemark.coordinate,
                address: item.placemark.title,
                phoneNumber: item.phoneNumber,
                website: item.url?.absoluteString
            )
        }
    }
}

extension Category {
    /// Best-effort mapping from MapKit's much larger category set onto this
    /// app's own categories, for pin color/icon purposes only.
    static func from(mapKitCategory: MKPointOfInterestCategory?) -> Category {
        switch mapKitCategory {
        case .restaurant: return .restaurant
        case .cafe, .bakery: return .cafe
        case .brewery, .winery, .nightlife, .distillery: return .bar
        case .hotel: return .hotel
        case .foodMarket: return .foodMarket
        default: return .location
        }
    }
}

private extension DiscoveredPlace {
    var clLocation: CLLocation { CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude) }
}
