//
//  PointOfInterestSearch.swift
//  Comebackone day 1.2
//
//  Generic live-MapKit place search — MKLocalPointsOfInterestRequest, ranked
//  by the "verified business" proxy (has phone + website) since Apple's
//  public MapKit API exposes no star rating for arbitrary businesses.
//  Originally built inside ItineraryPlanner for day-planning, moved out here
//  once the Find screen needed the exact same search/rank/name-filtering —
//  shared infrastructure two features depend on shouldn't live inside either
//  one's own file. ItineraryPlanner keeps its own tiling/diversity logic
//  (multi-stop-planning-specific), calling into these free functions for the
//  actual search.
//

import CoreLocation
import MapKit

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

enum PointOfInterestSearch {
    static func search(
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
    /// bare pin, and — within the same tier — the closer one wins.
    static func rank(_ places: [DiscoveredPlace], from origin: CLLocationCoordinate2D) -> [DiscoveredPlace] {
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        return places.sorted { lhs, rhs in
            let lhsScore = establishmentScore(lhs)
            let rhsScore = establishmentScore(rhs)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return originLocation.distance(from: lhs.clLocation) < originLocation.distance(from: rhs.clLocation)
        }
    }

    static func establishmentScore(_ place: DiscoveredPlace) -> Int {
        (place.website != nil ? 1 : 0) + (place.phoneNumber != nil ? 1 : 0)
    }

    /// A single query center, plus — once the requested radius meaningfully
    /// exceeds one tile's safe (pre-plateau) size — a couple of rings of
    /// additional tile centers spread across the requested area, searched
    /// concurrently and merged. Results are clipped back to the actually
    /// requested radius from the real origin, since an outer-ring tile's own
    /// circle can poke slightly past it.
    ///
    /// Exists because of a confirmed MapKit quirk: a single
    /// `MKLocalPointsOfInterestRequest` plateaus at a small, fixed set of
    /// results once its radius passes roughly 2-3km, and simply stops
    /// returning more no matter how much larger you set it — verified
    /// directly against Apple's API outside this app, at a real coordinate
    /// near Noosa, where a 3km, 5km, 25km, and 50km search all returned the
    /// exact same handful of places. Any caller offering a radius that can
    /// exceed ~2-3km needs to go through this, not a single `search(...)`
    /// call, or a distance picker option beyond that range will silently do
    /// nothing (confirmed live in the Find screen before this existed there).
    static func tiledResults(
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
}

extension DiscoveredPlace {
    var clLocation: CLLocation { CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude) }
}
