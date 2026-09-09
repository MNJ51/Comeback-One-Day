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

    /// The transport type for computing an actual on-road/path route via
    /// MKDirections, for the in-app route map (as opposed to the Apple Maps
    /// hand-off above).
    var mkDirectionsTransportType: MKDirectionsTransportType {
        switch self {
        case .walking: return .walking
        case .driving: return .automobile
        case .transit: return .transit
        }
    }
}

struct ItineraryStop: Identifiable {
    let place: DiscoveredPlace
    let isMysteryStop: Bool
    var id: UUID { place.id }
}

struct ItineraryResult {
    let stops: [ItineraryStop]
    /// The radius actually searched, in km — can exceed the distance the
    /// user picked if that radius didn't have enough places to fill a full
    /// day (see `ItineraryPlanner.searchUntilEnoughResults`).
    let searchedRadiusKm: Double
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
    ) async -> ItineraryResult {
        guard stopCount > 0 else { return ItineraryResult(stops: [], searchedRadiusKm: maxDistanceKm) }
        let requestedRadiusMeters = min(maxDistanceKm * 1000, 50_000)

        let (ranked, searchedRadiusMeters) = await searchUntilEnoughResults(
            categories: vibe.mapKitCategories,
            origin: origin,
            startingRadius: requestedRadiusMeters,
            minimumCount: stopCount
        )
        // A vibe like Foodie spans several MapKit categories (restaurant,
        // cafe, bakery, brewery, foodMarket...), but a beach town typically
        // has 3-4x as many restaurants as cafes. Taking a flat prefix() of
        // `ranked` after sorting by establishment score then distance let
        // restaurants — simply because there were so many close, verified
        // ones — fill every slot, leaving just a single cafe (or none) even
        // when a dozen were a few blocks away. Selecting round-robin across
        // category buckets guarantees the picks actually span the vibe.
        let picks = orderByProximity(selectDiverse(ranked, count: stopCount), from: origin)

        var stops = picks.map { ItineraryStop(place: $0, isMysteryStop: false) }

        if vibe != .mystery {
            let mysteryResults = await PointOfInterestSearch.tiledResults(categories: mysteryCategoryPool, origin: origin, requestedRadius: searchedRadiusMeters)
            let usedNames = Set(picks.map { $0.name.lowercased() })
            if let mystery = PointOfInterestSearch.rank(mysteryResults, from: origin)
                .first(where: { !usedNames.contains($0.name.lowercased()) && !PointOfInterestSearch.nameSuggestsUnrelatedProfessionalService($0.name) }) {
                stops.append(ItineraryStop(place: mystery, isMysteryStop: true))
            }
        }

        return ItineraryResult(stops: stops, searchedRadiusKm: searchedRadiusMeters / 1000)
    }

    /// Doubles the radius (up to MapKit's 50km search ceiling), re-tiling
    /// each time via `PointOfInterestSearch.tiledResults`, until there are
    /// enough unique places to fill a full day.
    private static func searchUntilEnoughResults(
        categories: [MKPointOfInterestCategory],
        origin: CLLocationCoordinate2D,
        startingRadius: CLLocationDistance,
        minimumCount: Int
    ) async -> (ranked: [DiscoveredPlace], radius: CLLocationDistance) {
        var radius = startingRadius
        var ranked = await PointOfInterestSearch.tiledResults(categories: categories, origin: origin, requestedRadius: radius)

        while ranked.count < minimumCount, radius < 50_000 {
            radius = min(radius * 2, 50_000)
            ranked = await PointOfInterestSearch.tiledResults(categories: categories, origin: origin, requestedRadius: radius)
        }

        return (ranked, radius)
    }

    /// Greedy nearest-neighbor walk starting from `origin`: repeatedly picks
    /// whichever remaining place is closest to wherever the walk currently
    /// is, not whichever was closest to the *original* starting point. This
    /// is what makes the stop numbering (and the route map's polyline)
    /// actually flow across the area instead of jumping back and forth —
    /// it's an approximation (true optimal-route TSP is overkill for ~10
    /// stops), but it's the difference between a walkable day and a
    /// scavenger hunt.
    static func orderByProximity(_ places: [DiscoveredPlace], from origin: CLLocationCoordinate2D) -> [DiscoveredPlace] {
        var remaining = places
        var ordered: [DiscoveredPlace] = []
        var current = CLLocation(latitude: origin.latitude, longitude: origin.longitude)

        while !remaining.isEmpty {
            let nearestIndex = remaining.indices.min { lhs, rhs in
                current.distance(from: remaining[lhs].clLocation) < current.distance(from: remaining[rhs].clLocation)
            }!
            let nearest = remaining.remove(at: nearestIndex)
            ordered.append(nearest)
            current = nearest.clLocation
        }

        return ordered
    }

    /// Picks `count` places round-robin across `ranked`'s category buckets
    /// (preserving each bucket's internal quality/distance order) instead of
    /// taking a flat prefix, so an abundant category can't crowd out a
    /// sparser one just by outnumbering it in the raw search results.
    static func selectDiverse(_ ranked: [DiscoveredPlace], count: Int) -> [DiscoveredPlace] {
        guard count > 0 else { return [] }

        // Buckets on MapKit's own fine-grained category (raw value string),
        // not the app's coarse `Category` — otherwise every non-food vibe
        // (Adventure, Relaxed, Culture) collapses onto the single `.location`
        // bucket and this round-robin has nothing left to actually diversify.
        func bucketKey(_ place: DiscoveredPlace) -> String {
            place.mapKitCategory?.rawValue ?? "unknown"
        }

        var buckets: [String: [DiscoveredPlace]] = [:]
        var bucketOrder: [String] = []
        for place in ranked {
            let key = bucketKey(place)
            if buckets[key] == nil {
                buckets[key] = []
                bucketOrder.append(key)
            }
            buckets[key]?.append(place)
        }

        var nextIndex: [String: Int] = [:]
        var selected: [DiscoveredPlace] = []
        while selected.count < count {
            var madeProgress = false
            for key in bucketOrder {
                guard selected.count < count else { break }
                let index = nextIndex[key] ?? 0
                guard let bucket = buckets[key], index < bucket.count else { continue }
                selected.append(bucket[index])
                nextIndex[key] = index + 1
                madeProgress = true
            }
            if !madeProgress { break }
        }

        return selected
    }
}
