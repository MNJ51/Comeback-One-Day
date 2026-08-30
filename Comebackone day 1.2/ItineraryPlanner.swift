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
    case cafe = "Cafe"
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
        case .relaxed: return "leaf.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .adventure: return "figure.hiking"
        case .foodie: return "fork.knife"
        case .culture: return "building.columns.fill"
        case .mystery: return "questionmark.diamond.fill"
        }
    }

    /// The MapKit categories searched for this vibe. Every case here is a
    /// confirmed MKPointOfInterestCategory member available on iOS 18.
    /// Kept tight and category-pure on purpose — Cafe only searches cafes,
    /// not a grab-bag that happens to include a couple of coffee shops.
    var mapKitCategories: [MKPointOfInterestCategory] {
        switch self {
        case .relaxed:
            return [.park, .beach, .spa, .winery, .nightlife]
        case .cafe:
            return [.cafe, .bakery]
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
    /// best matches for the vibe (see `rank`), plus (for non-Mystery vibes)
    /// one bonus stop from the offbeat Mystery pool, revealed only when tapped.
    /// Defaults to a full day (9 stops + 1 Mystery bonus = 10) rather than a
    /// quick handful — this is the paid tier, it should feel like a full day
    /// out, not a snack.
    static func discover(
        vibe: ItineraryVibe,
        origin: CLLocationCoordinate2D,
        maxDistanceKm: Double,
        stopCount: Int = 9
    ) async -> [ItineraryStop] {
        guard stopCount > 0 else { return [] }
        let radiusMeters = min(maxDistanceKm * 1000, 50_000)

        let mainResults = await search(categories: vibe.mapKitCategories, center: origin, radius: radiusMeters)
        var seenNames = Set<String>()
        let ranked = rank(mainResults, from: origin)
            .filter { seenNames.insert($0.name.lowercased()).inserted }
        let picks = Array(ranked.prefix(stopCount))

        var stops = picks.map { ItineraryStop(place: $0, isMysteryStop: false) }

        if vibe != .mystery {
            let mysteryResults = await search(categories: mysteryCategoryPool, center: origin, radius: radiusMeters)
            let usedNames = Set(picks.map { $0.name.lowercased() })
            if let mystery = rank(mysteryResults, from: origin)
                .first(where: { !usedNames.contains($0.name.lowercased()) }) {
                stops.append(ItineraryStop(place: mystery, isMysteryStop: true))
            }
        }

        return stops
    }

    /// MapKit exposes no rating or popularity signal for arbitrary businesses,
    /// so "top" here means the best free proxy available: a verifiable,
    /// established business (has a website and a phone number) ranks above a
    /// bare pin, and — within the same tier — the closer one wins. That
    /// second part matters: it's what makes the distance picker actually
    /// change the results instead of just changing the search radius while
    /// the same handful of places keep winning regardless.
    static func rank(_ places: [DiscoveredPlace], from origin: CLLocationCoordinate2D) -> [DiscoveredPlace] {
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        return places.sorted { lhs, rhs in
            let lhsScore = establishmentScore(lhs)
            let rhsScore = establishmentScore(rhs)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return originLocation.distance(from: lhs.clLocation) < originLocation.distance(from: rhs.clLocation)
        }
    }

    private static func establishmentScore(_ place: DiscoveredPlace) -> Int {
        (place.website != nil ? 1 : 0) + (place.phoneNumber != nil ? 1 : 0)
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
