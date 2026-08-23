//
//  ItineraryPlanner.swift
//  Comebackone day 1.2
//
//  Itinerary generation searches real nearby places live via the Google
//  Places API (New) rather than the user's saved places. Unlike MapKit,
//  Google's API exposes star ratings, review counts, editorial summaries,
//  and photos — which is what makes a "top-rated restaurants only" filter
//  and real photos in the results possible at all.
//

import CoreLocation
import Foundation
import MapKit

enum ItineraryVibe: String, CaseIterable, Identifiable {
    case relaxed = "Relaxed"
    case adventure = "Adventure"
    case foodie = "Foodie"
    case culture = "Culture"
    /// Deliberately searches an unusual category pool (go-karts, planetariums,
    /// water parks...) instead of the vibe's usual categories, so the plan
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

    /// The Google Places (New) types searched for this vibe. Every value here
    /// is a confirmed literal from Google's Table A place-type list.
    var includedTypes: [String] {
        switch self {
        case .relaxed:
            return ["cafe", "coffee_shop", "park", "beach", "spa", "winery", "botanical_garden", "garden"]
        case .adventure:
            return ["park", "national_park", "state_park", "hiking_area", "campground", "marina", "beach", "adventure_sports_center", "off_roading_area"]
        case .foodie:
            return ["restaurant", "fine_dining_restaurant", "seafood_restaurant", "steakhouse", "bar_and_grill", "cafe", "bakery", "brewery", "winery", "bar", "pub"]
        case .culture:
            return ["museum", "art_gallery", "art_museum", "history_museum", "historical_place", "historical_landmark", "cultural_landmark", "monument", "castle", "planetarium", "performing_arts_theater", "concert_hall", "live_music_venue", "movie_theater"]
        case .mystery:
            return ItineraryPlanner.mysteryTypes
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

/// A place found via live Google Places search — not a saved TravelMemory,
/// so it carries its own rating/photo rather than the user's own.
struct DiscoveredPlace: Identifiable {
    let id = UUID()
    let name: String
    let category: Category
    let coordinate: CLLocationCoordinate2D
    let address: String?
    let phoneNumber: String?
    let website: String?
    let rating: Double?
    let userRatingCount: Int?
    let summary: String?
    let photoURL: URL?
}

struct ItineraryStop: Identifiable {
    let place: DiscoveredPlace
    let isMysteryStop: Bool
    var id: UUID { place.id }
}

enum ItineraryPlanner {
    /// Offbeat types used both for Mystery-vibe's main search and as the
    /// bonus Mystery Stop pool for every other vibe.
    static let mysteryTypes: [String] = [
        "zoo", "aquarium", "planetarium", "go_karting_venue", "miniature_golf_course",
        "skateboard_park", "amusement_park", "water_park", "roller_coaster",
        "ferris_wheel", "karaoke", "comedy_club", "botanical_garden"
    ]

    /// A place is confidently "top-rated" once it has both a high score and
    /// enough reviews behind it — a 5.0 from two reviews isn't trustworthy.
    static let minTopRatedScore = 4.0
    static let minTopRatedReviewCount = 10

    /// Searches real nearby places live via Google Places and builds a day out
    /// of the best matches for the vibe, ranked by a blend of rating and
    /// distance (not just nearest-first) so the plan favors genuinely good
    /// stops over merely convenient ones. Adds one bonus stop from the offbeat
    /// Mystery pool for non-Mystery vibes, revealed only when tapped.
    static func discover(
        vibe: ItineraryVibe,
        origin: CLLocationCoordinate2D,
        maxDistanceKm: Double,
        stopCount: Int = 4,
        topRatedRestaurantsOnly: Bool = false
    ) async -> [ItineraryStop] {
        guard stopCount > 0 else { return [] }
        let radiusMeters = min(maxDistanceKm * 1000, 50_000)
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)

        var mainResults = await search(types: vibe.includedTypes, center: origin, radius: radiusMeters)
        if topRatedRestaurantsOnly {
            mainResults = mainResults.filter { place in
                guard place.category == .restaurant else { return true }
                return (place.rating ?? 0) >= minTopRatedScore
            }
        }

        var seenNames = Set<String>()
        let ranked = mainResults
            .sorted { score(for: $0, from: originLocation) > score(for: $1, from: originLocation) }
            .filter { seenNames.insert($0.name.lowercased()).inserted }
        let picks = Array(ranked.prefix(stopCount))

        var stops = picks.map { ItineraryStop(place: $0, isMysteryStop: false) }

        if vibe != .mystery {
            let mysteryResults = await search(types: mysteryTypes, center: origin, radius: radiusMeters)
            let usedNames = Set(picks.map { $0.name.lowercased() })
            if let mystery = mysteryResults
                .sorted(by: { score(for: $0, from: originLocation) > score(for: $1, from: originLocation) })
                .first(where: { !usedNames.contains($0.name.lowercased()) }) {
                stops.append(ItineraryStop(place: mystery, isMysteryStop: true))
            }
        }

        return stops
    }

    /// Rewards higher ratings while still mildly penalizing distance, so a
    /// 4.8★ place a bit further away can beat a mediocre one right next door.
    private static func score(for place: DiscoveredPlace, from origin: CLLocation) -> Double {
        let distanceKm = origin.distance(from: place.clLocation) / 1000
        let rating = place.rating ?? 3.8
        return rating - (distanceKm * 0.15)
    }

    private static func search(
        types: [String],
        center: CLLocationCoordinate2D,
        radius: CLLocationDistance
    ) async -> [DiscoveredPlace] {
        let places = await GooglePlacesService.searchNearby(includedTypes: types, center: center, radiusMeters: radius)
        return places.map { place in
            DiscoveredPlace(
                name: place.name,
                category: Category.from(googleTypes: place.types, primaryType: place.primaryType),
                coordinate: place.coordinate,
                address: place.address,
                phoneNumber: place.phoneNumber,
                website: place.website,
                rating: place.rating,
                userRatingCount: place.userRatingCount,
                summary: place.summary,
                photoURL: place.photoName.flatMap { GooglePlacesService.photoURL(photoName: $0) }
            )
        }
    }
}

extension Category {
    private static let restaurantTypes: Set<String> = [
        "restaurant", "fine_dining_restaurant", "fast_food_restaurant", "seafood_restaurant",
        "steakhouse", "mexican_restaurant", "pizza_restaurant", "bar_and_grill",
        "barbecue_restaurant", "deli", "food_court", "ice_cream_shop", "donut_shop"
    ]
    private static let cafeTypes: Set<String> = ["cafe", "coffee_shop", "bakery"]
    private static let barTypes: Set<String> = ["bar", "pub", "brewery", "winery", "night_club"]
    private static let hotelTypes: Set<String> = [
        "hotel", "lodging", "bed_and_breakfast", "hostel", "motel", "resort_hotel",
        "inn", "guest_house", "extended_stay_hotel", "cottage", "farmstay"
    ]
    private static let foodMarketTypes: Set<String> = [
        "grocery_store", "supermarket", "farmers_market", "market", "food_store"
    ]

    /// Best-effort mapping from Google's much larger type set onto this app's
    /// own categories, for pin color/icon purposes only.
    static func from(googleTypes: [String], primaryType: String?) -> Category {
        var candidates = googleTypes
        if let primaryType { candidates = [primaryType] + candidates }
        for type in candidates {
            if restaurantTypes.contains(type) { return .restaurant }
            if cafeTypes.contains(type) { return .cafe }
            if barTypes.contains(type) { return .bar }
            if hotelTypes.contains(type) { return .hotel }
            if foodMarketTypes.contains(type) { return .foodMarket }
        }
        return .location
    }
}

private extension DiscoveredPlace {
    var clLocation: CLLocation { CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude) }
}
