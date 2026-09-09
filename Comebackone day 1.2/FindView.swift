//
//  FindView.swift
//  Comebackone day 1.2
//
//  Nearby restaurant discovery — searches real places live via MapKit within
//  ~1km of the user (PointOfInterestSearch, the same search/rank/name-filter
//  infrastructure Itinerary uses), filterable by cuisine (name-keyword
//  heuristic, since MapKit has no cuisine field) and a "verified places only"
//  toggle (has phone + website — MapKit exposes no real star rating, same
//  proxy Itinerary already uses; a real ratings API was deliberately deferred
//  rather than embedding a third-party API key with no backend to protect
//  it). Tapping a result reuses ItineraryView's DiscoveredPlaceDetailSheet —
//  already built for "view a live-searched place, then save it" — rather
//  than a second, parallel flow.
//

import SwiftUI
import MapKit

/// Bottom-bar entry point, mirroring ItineraryButton's exact self-contained
/// shape: owns its own sheet state so presenting it doesn't churn anything
/// else in the bar.
struct FindButton: View {
    @EnvironmentObject var store: MemoryStore
    @EnvironmentObject var locationManager: LocationManager
    @State private var showingFind = false

    var body: some View {
        Button {
            showingFind = true
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 21))
                Text("Find")
                    .font(.caption2)
            }
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingFind) {
            FindView()
                .environmentObject(store)
                .environmentObject(locationManager)
        }
    }
}

struct FindView: View {
    @EnvironmentObject var store: MemoryStore
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    /// A restaurant search stays close to actual dining categories — unlike
    /// Itinerary's Foodie vibe, which deliberately also spans brewery/winery/
    /// distillery. Multi-category on purpose: a single `.restaurant`-only
    /// search misses real restaurants MapKit tags under an adjacent category,
    /// a mistake already made and fixed once in the itinerary feature.
    private static let searchCategories: [MKPointOfInterestCategory] = [.restaurant, .cafe, .bakery, .foodMarket]
    private static let radiusOptionsKm: [Double] = [0.5, 1.0, 2.0, 5.0]
    private static let fallbackLocationTimeout: Duration = .seconds(8)
    private static let fallbackCoordinate = CLLocationCoordinate2D(latitude: -27.4705, longitude: 153.0260)

    /// Bundles both conditions a search should re-run on into one `.task(id:)`
    /// key — location becoming available, and the user picking a different
    /// radius — so there's exactly one search-triggering task, not two racing
    /// or double-firing ones. `.task(id:)` auto-cancels the previous run the
    /// moment the id changes, which is what makes changing the radius safe
    /// even while an earlier search is still in flight.
    private struct SearchTrigger: Equatable {
        var waiting: Bool
        var radiusKm: Double
    }

    @State private var cameraPosition = MapCameraPosition.userLocation(
        fallback: .region(MKCoordinateRegion(
            center: fallbackCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))
    )
    @State private var radiusKm: Double = 1.0
    @State private var results: [DiscoveredPlace] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var selectedCuisine: Cuisine?
    @State private var verifiedOnly = false
    @State private var selectedPlace: DiscoveredPlace?
    @State private var locationTimedOut = false
    @State private var userAcceptedFallbackLocation = false
    /// Tags each map tap so a slow earlier resolve can't overwrite a later,
    /// faster tap's result — same guard `AdjustLocationView` already uses.
    @State private var pendingTapID: UUID?

    private var origin: CLLocationCoordinate2D {
        locationManager.currentLocation ?? Self.fallbackCoordinate
    }

    /// Same shape as ItineraryPlannerView's own wait-for-a-fix state: blocks
    /// searching around the hardcoded fallback the moment this screen opens,
    /// which would otherwise silently search a location away from wherever
    /// the user actually is with no indication anything was off.
    private var isWaitingForLocation: Bool {
        locationManager.currentLocation == nil
            && !locationManager.isDenied
            && !(locationTimedOut && userAcceptedFallbackLocation)
    }

    private var filteredResults: [DiscoveredPlace] {
        results.filter { place in
            if let selectedCuisine, !selectedCuisine.matches(name: place.name) { return false }
            if verifiedOnly, PointOfInterestSearch.establishmentScore(place) == 0 { return false }
            return true
        }
    }

    /// A place already on screen within a few meters of a tapped point, if
    /// any — checked before falling back to an async MapKit lookup so a tap
    /// directly on one of the app's own result pins resolves instantly.
    private func nearbyResult(to coordinate: CLLocationCoordinate2D) -> DiscoveredPlace? {
        let tapped = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return filteredResults.first { tapped.distance(from: $0.clLocation) <= 20 }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isWaitingForLocation {
                    waitingForLocationView
                } else {
                    resultsView
                }
            }
            .navigationTitle("Find")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task(id: locationManager.currentLocation == nil) {
                guard locationManager.currentLocation == nil, !locationManager.isDenied else { return }
                try? await Task.sleep(for: Self.fallbackLocationTimeout)
                guard !Task.isCancelled else { return }
                locationTimedOut = true
            }
            .task(id: SearchTrigger(waiting: isWaitingForLocation, radiusKm: radiusKm)) {
                guard !isWaitingForLocation else { return }
                await search()
            }
            .sheet(item: $selectedPlace) { place in
                DiscoveredPlaceDetailSheet(place: place, travelMode: .walking)
                    .environmentObject(store)
            }
        }
    }

    private var waitingForLocationView: some View {
        VStack(spacing: 16) {
            if locationTimedOut {
                Label("Still no location after a few seconds — check you have a clear view of the sky, or Wi-Fi/cellular is on.", systemImage: "location.slash.fill")
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Search Near a Default Location Instead") {
                    userAcceptedFallbackLocation = true
                }
            } else {
                ProgressView()
                Text("Finding your location…")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if locationManager.currentLocation == nil {
                    Label("Searching near a default location — your device's real location wasn't available.", systemImage: "location.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                }

                Picker("Distance", selection: $radiusKm) {
                    ForEach(Self.radiusOptionsKm, id: \.self) { km in
                        Text(km < 1 ? "\(Int(km * 1000)) m" : "\(km.formatted(.number.precision(.fractionLength(0...1)))) km").tag(km)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "All", color: .gray, isSelected: selectedCuisine == nil) {
                            selectedCuisine = nil
                        }
                        ForEach(Cuisine.allCases) { cuisine in
                            FilterChip(title: cuisine.rawValue, color: .orange, isSelected: selectedCuisine == cuisine) {
                                selectedCuisine = selectedCuisine == cuisine ? nil : cuisine
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                Toggle("Verified places only", isOn: $verifiedOnly)
                    .padding(.horizontal)
                    .toggleStyle(.switch)

                if hasSearched {
                    Text(resultCountLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, 8)

            ZStack {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        UserAnnotation()
                        ForEach(filteredResults) { place in
                            Annotation(place.name, coordinate: place.coordinate) {
                                FindResultPin(place: place)
                                    .onTapGesture { selectedPlace = place }
                            }
                        }
                    }
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                            handleMapTap(at: coordinate)
                        }
                    )
                }
                .ignoresSafeArea(edges: .bottom)

                if isSearching {
                    ProgressView("Searching nearby…")
                        .padding()
                        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
                } else if hasSearched, filteredResults.isEmpty {
                    Text(results.isEmpty ? "No restaurants found nearby." : "No results match these filters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding()
                        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var resultCountLabel: String {
        let total = results.count
        let shown = filteredResults.count
        if shown == total {
            return total == 1 ? "1 nearby" : "\(total) nearby"
        }
        return "\(shown) of \(total) nearby"
    }

    /// Tapping anywhere on the map — including Apple's own native restaurant
    /// icons, which aren't part of this app's own annotations and so have no
    /// tap handler of their own — resolves to whichever business is nearest.
    /// Checks the app's own already-loaded results first (instant, no
    /// network call); only falls back to a live MapKit lookup for a tap that
    /// doesn't land on one of those. Deliberately bypasses the cuisine/
    /// verified filters: a direct tap on a specific icon is unambiguous
    /// intent, and the whole point of this is surfacing places the filter
    /// heuristic missed.
    private func handleMapTap(at coordinate: CLLocationCoordinate2D) {
        if let match = nearbyResult(to: coordinate) {
            selectedPlace = match
            return
        }

        let tapID = UUID()
        pendingTapID = tapID
        Task {
            guard let match = await LocationSearchService.nearestPlace(to: coordinate) else { return }
            guard pendingTapID == tapID else { return }
            selectedPlace = DiscoveredPlace(
                name: match.name,
                category: Category.from(mapKitCategory: match.mapKitCategory),
                coordinate: match.coordinate,
                address: match.address,
                phoneNumber: match.phoneNumber,
                website: match.website,
                mapKitCategory: match.mapKitCategory
            )
        }
    }

    private func search() async {
        isSearching = true
        // tiledResults, not a single search(...) call — a plain untiled
        // request plateaus at a small, fixed result set past ~2-3km, which
        // the 2km/5km distance options here can exceed (confirmed live: a
        // 500m, 1km, and 5km search all returned the exact same 47 places
        // before this used tiling).
        let found = await PointOfInterestSearch.tiledResults(categories: Self.searchCategories, origin: origin, requestedRadius: radiusKm * 1000)
        // MKLocalSearch may keep running after this Task is cancelled (e.g. the
        // radius changed again before this call returned) — guard the write so
        // a slow, superseded search can't clobber fresher results that already
        // landed.
        guard !Task.isCancelled else { return }
        // tiledResults already ranks, dedupes, and filters out mistagged
        // listings internally — no need to redo any of that here.
        results = found
        isSearching = false
        hasSearched = true
    }
}

/// Icon-only pin (no saved photo exists yet for a place that isn't a
/// TravelMemory) — same category color/icon language as MemoryPin elsewhere.
private struct FindResultPin: View {
    let place: DiscoveredPlace

    var body: some View {
        Image(systemName: place.category.icon)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(8)
            .background(place.category.color, in: Circle())
            .shadow(radius: 3)
    }
}
