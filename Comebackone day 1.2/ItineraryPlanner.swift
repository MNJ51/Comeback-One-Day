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
    /// MapKit's own, much finer-grained category (hiking trail vs. beach vs.
    /// national park vs. generic park, etc.) — kept alongside the app's own
    /// coarser `Category` (used for pin color/icon everywhere else) so
    /// itinerary selection can spread across genuinely different KINDS of
    /// place. `Category.from(mapKitCategory:)` maps almost everything
    /// non-food to a single `.location` bucket, which made a vibe like
    /// Adventure — spanning parks, hiking, beaches, kayaking, surfing — get
    /// zero benefit from `selectDiverse`'s round-robin: every stop landed in
    /// that one bucket, so it silently fell back to flat closest-first
    /// ranking, often just a run of generic suburban parks.
    var mapKitCategory: MKPointOfInterestCategory?
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
            let mysteryResults = await tiledResults(categories: mysteryCategoryPool, origin: origin, requestedRadius: searchedRadiusMeters)
            let usedNames = Set(picks.map { $0.name.lowercased() })
            if let mystery = rank(mysteryResults, from: origin)
                .first(where: { !usedNames.contains($0.name.lowercased()) && !nameSuggestsUnrelatedProfessionalService($0.name) }) {
                stops.append(ItineraryStop(place: mystery, isMysteryStop: true))
            }
        }

        return ItineraryResult(stops: stops, searchedRadiusKm: searchedRadiusMeters / 1000)
    }

    /// Tiles the requested radius into several smaller searches instead of
    /// one big one, and — if that still doesn't turn up enough unique places
    /// — doubles the radius (up to MapKit's 50km search ceiling) and tiles
    /// again.
    ///
    /// The tiling exists because of a confirmed MapKit quirk: a single
    /// `MKLocalPointsOfInterestRequest` plateaus at a small, fixed set of
    /// results once its radius passes roughly 2-3km, and simply stops
    /// returning more no matter how much larger you set it — verified
    /// directly against Apple's API outside this app, at a real coordinate
    /// near Noosa, where a 3km, 5km, 25km, and 50km search all returned the
    /// exact same handful of places. That made the distance picker feel
    /// broken: picking 25km instead of 5km visibly did nothing. Splitting
    /// the requested area into several ~2.5km tiles and merging their
    /// results actually reflects the area the user asked for. Every tile is
    /// still ranked/sorted by true distance from the real origin, not from
    /// whichever tile center happened to find it.
    private static func searchUntilEnoughResults(
        categories: [MKPointOfInterestCategory],
        origin: CLLocationCoordinate2D,
        startingRadius: CLLocationDistance,
        minimumCount: Int
    ) async -> (ranked: [DiscoveredPlace], radius: CLLocationDistance) {
        var radius = startingRadius
        var ranked = await tiledResults(categories: categories, origin: origin, requestedRadius: radius)

        while ranked.count < minimumCount, radius < 50_000 {
            radius = min(radius * 2, 50_000)
            ranked = await tiledResults(categories: categories, origin: origin, requestedRadius: radius)
        }

        return (ranked, radius)
    }

    /// A single query center, plus — once the requested radius meaningfully
    /// exceeds one tile's safe (pre-plateau) size — a couple of rings of
    /// additional tile centers spread across the requested area, searched
    /// concurrently and merged. Results are clipped back to the actually
    /// requested radius from the real origin, since an outer-ring tile's own
    /// circle can poke slightly past it.
    private static func tiledResults(
        categories: [MKPointOfInterestCategory],
        origin: CLLocationCoordinate2D,
        requestedRadius: CLLocationDistance
    ) async -> [DiscoveredPlace] {
        let tileRadius = min(requestedRadius, 2_500)
        var centers = [origin]

        if requestedRadius > tileRadius * 1.5 {
            let metersPerDegreeLatitude = 111_000.0
            let metersPerDegreeLongitude = 111_000.0 * cos(origin.latitude * .pi / 180)
            for ringFraction in [0.4, 0.75] {
                let ringDistance = requestedRadius * ringFraction
                for degrees in stride(from: 0.0, to: 360.0, by: 45.0) {
                    let radians = degrees * .pi / 180
                    let latOffset = (ringDistance * cos(radians)) / metersPerDegreeLatitude
                    let lonOffset = (ringDistance * sin(radians)) / metersPerDegreeLongitude
                    centers.append(CLLocationCoordinate2D(latitude: origin.latitude + latOffset, longitude: origin.longitude + lonOffset))
                }
            }
        }

        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let tileResults = await withTaskGroup(of: [DiscoveredPlace].self) { group in
            for center in centers {
                group.addTask { await search(categories: categories, center: center, radius: tileRadius) }
            }
            var all: [DiscoveredPlace] = []
            for await results in group { all.append(contentsOf: results) }
            return all
        }

        var seenNames = Set<String>()
        return rank(tileResults, from: origin)
            .filter { seenNames.insert($0.name.lowercased()).inserted }
            .filter { originLocation.distance(from: $0.clLocation) <= requestedRadius }
            .filter { !nameSuggestsUnrelatedProfessionalService($0.name) }
    }

    /// A small number of MapKit listings have complete, legitimate-looking
    /// business info (phone + website — the exact signal `rank` trusts) but
    /// are tagged with a category that plainly doesn't match the business:
    /// an interior design studio filed under Kayaking, a meditation practice
    /// under Food Market. There's no free way to verify a listing's true
    /// category against a real source, but a business whose own name reads
    /// as an unrelated professional service is safe to drop outright — a
    /// real kayaking outfitter or park is never going to be named like this.
    private static let unrelatedProfessionalServiceKeywords = [
        "design", "consulting", "accounting", "accountant", "realty", "real estate",
        "insurance", "law firm", "lawyer", "solicitor", "attorney", "dental",
        "dentist", "medical centre", "medical center", "clinic", "physiotherapy",
        "chiropractic", "bookkeeping", "financial planning", "mortgage broker"
    ]

    static func nameSuggestsUnrelatedProfessionalService(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return unrelatedProfessionalServiceKeywords.contains { lowered.contains($0) }
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
                website: item.url?.absoluteString,
                mapKitCategory: item.pointOfInterestCategory
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
