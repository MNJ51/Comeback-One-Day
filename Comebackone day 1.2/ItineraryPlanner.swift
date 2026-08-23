//
//  ItineraryPlanner.swift
//  Comebackone day 1.2
//
//  Pure day-itinerary generation logic (no StoreKit, no UI) so the algorithm
//  itself is fully unit-testable independent of the subscription gate.
//

import CoreLocation
import MapKit

enum ItineraryVibe: String, CaseIterable, Identifiable {
    case relaxed = "Relaxed"
    case adventure = "Adventure"
    case foodie = "Foodie"
    case culture = "Culture"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .relaxed: return "cup.and.saucer.fill"
        case .adventure: return "figure.hiking"
        case .foodie: return "fork.knife"
        case .culture: return "building.columns.fill"
        }
    }

    /// How well a place category fits this vibe. Every category still scores
    /// above zero so nothing is hard-excluded — a great-rated place just outside
    /// the vibe can still make the cut.
    func weight(for category: Category) -> Double {
        switch (self, category) {
        case (.foodie, .restaurant): return 3
        case (.foodie, .foodMarket): return 3
        case (.foodie, .cafe): return 2
        case (.foodie, .bar): return 1.5

        case (.relaxed, .cafe): return 3
        case (.relaxed, .bar): return 2
        case (.relaxed, .hotel): return 1.5

        case (.adventure, .location): return 3
        case (.adventure, .foodMarket): return 1.5

        case (.culture, .location): return 2.5
        case (.culture, .hotel): return 1.5
        case (.culture, .cafe): return 1.2

        default: return 1
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

struct ItineraryStop: Identifiable, Equatable {
    let memory: TravelMemory
    let isMysteryStop: Bool
    var id: UUID { memory.id }
}

enum ItineraryPlanner {
    /// Builds a day itinerary from the nearest, best vibe-fitting places, ordered
    /// into a simple nearest-neighbor route from `origin`, plus one Mystery Stop —
    /// a wishlist place from outside the obvious top picks, so it's a genuine
    /// surprise rather than just another rated-highly pick.
    static func generate<RNG: RandomNumberGenerator>(
        from memories: [TravelMemory],
        vibe: ItineraryVibe,
        origin: CLLocationCoordinate2D,
        stopCount: Int = 4,
        maxDistanceKm: Double = 5,
        glutenFreeOnly: Bool = false,
        topRatedRestaurantsOnly: Bool = false,
        using rng: inout RNG
    ) -> [ItineraryStop] {
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let withinRange = memories.filter { originLocation.distance(from: $0.clLocation) / 1000 <= maxDistanceKm }
        let glutenFreeFiltered = filterGlutenFree(withinRange, glutenFreeOnly: glutenFreeOnly)
        let eligible = filterTopRatedRestaurants(glutenFreeFiltered, topRatedRestaurantsOnly: topRatedRestaurantsOnly)
        guard !eligible.isEmpty, stopCount > 0 else { return [] }

        func score(_ memory: TravelMemory) -> Double {
            let vibeWeight = vibe.weight(for: memory.category)
            let ratingBoost = Double(memory.rating) * 0.3
            let distanceKm = originLocation.distance(from: memory.clLocation) / 1000
            let distancePenalty = distanceKm * 0.05
            return vibeWeight + ratingBoost - distancePenalty
        }

        let ranked = eligible.sorted { score($0) > score($1) }
        let picks = Array(ranked.prefix(stopCount))

        // Route the picks with a simple nearest-neighbor walk from origin —
        // not optimal, but avoids obvious criss-crossing for a handful of stops.
        var remaining = picks
        var route: [TravelMemory] = []
        var current = originLocation
        while !remaining.isEmpty {
            let next = remaining.min { current.distance(from: $0.clLocation) < current.distance(from: $1.clLocation) }!
            route.append(next)
            current = next.clLocation
            remaining.removeAll { $0.id == next.id }
        }

        var stops = route.map { ItineraryStop(memory: $0, isMysteryStop: false) }

        if let mystery = mysteryCandidate(excluding: route, in: eligible, vibe: vibe, origin: origin, using: &rng) {
            stops.append(ItineraryStop(memory: mystery, isMysteryStop: true))
        }

        return stops
    }

    static func generate(
        from memories: [TravelMemory],
        vibe: ItineraryVibe,
        origin: CLLocationCoordinate2D,
        stopCount: Int = 4,
        maxDistanceKm: Double = 5,
        glutenFreeOnly: Bool = false,
        topRatedRestaurantsOnly: Bool = false
    ) -> [ItineraryStop] {
        var rng = SystemRandomNumberGenerator()
        return generate(from: memories, vibe: vibe, origin: origin, stopCount: stopCount, maxDistanceKm: maxDistanceKm, glutenFreeOnly: glutenFreeOnly, topRatedRestaurantsOnly: topRatedRestaurantsOnly, using: &rng)
    }

    /// Keeps every non-food place as-is; when `glutenFreeOnly` is on, food-related
    /// places (restaurants, cafes, bars, markets) are kept only if flagged
    /// gluten-free. A place that isn't food-related has nothing to filter on, so
    /// it's never excluded by this option.
    private static func filterGlutenFree(_ memories: [TravelMemory], glutenFreeOnly: Bool) -> [TravelMemory] {
        guard glutenFreeOnly else { return memories }
        return memories.filter { !$0.category.isFoodRelated || $0.isGlutenFree }
    }

    /// Ratings are whole stars (1–5) — there's no literal "4.5" to filter on, so
    /// this uses 4★ and up as the closest real equivalent. Only restaurants are
    /// affected; every other category passes through untouched.
    private static func filterTopRatedRestaurants(_ memories: [TravelMemory], topRatedRestaurantsOnly: Bool) -> [TravelMemory] {
        guard topRatedRestaurantsOnly else { return memories }
        return memories.filter { $0.category != .restaurant || $0.rating >= 4 }
    }

    /// The pool a Mystery Stop can be drawn from: wishlist places not already
    /// on the route, restricted to the lower-scoring half so it's not just
    /// another obvious top pick. Exposed separately so its composition (not
    /// just the final random choice) can be tested deterministically.
    static func mysteryPool(
        excluding route: [TravelMemory],
        in memories: [TravelMemory],
        vibe: ItineraryVibe,
        origin: CLLocationCoordinate2D
    ) -> [TravelMemory] {
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        func score(_ memory: TravelMemory) -> Double {
            let vibeWeight = vibe.weight(for: memory.category)
            let ratingBoost = Double(memory.rating) * 0.3
            let distanceKm = originLocation.distance(from: memory.clLocation) / 1000
            return vibeWeight + ratingBoost - distanceKm * 0.05
        }

        let routeIDs = Set(route.map(\.id))
        let candidates = memories.filter { $0.visitStatus == .wantToGo && !routeIDs.contains($0.id) }
        let ranked = candidates.sorted { score($0) > score($1) }
        return ranked.count > 2 ? Array(ranked.dropFirst(ranked.count / 2)) : ranked
    }

    private static func mysteryCandidate<RNG: RandomNumberGenerator>(
        excluding route: [TravelMemory],
        in memories: [TravelMemory],
        vibe: ItineraryVibe,
        origin: CLLocationCoordinate2D,
        using rng: inout RNG
    ) -> TravelMemory? {
        mysteryPool(excluding: route, in: memories, vibe: vibe, origin: origin).randomElement(using: &rng)
    }
}

private extension TravelMemory {
    var clLocation: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}
