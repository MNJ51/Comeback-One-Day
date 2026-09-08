//
//  ItineraryView.swift
//  Comebackone day 1.2
//

import SwiftUI
import MapKit
import StoreKit

/// Toolbar entry point, isolated in its own view for the same reason as
/// SettingsButton: owning the EnvironmentObjects here (rather than on the
/// screen this sits inside) keeps their publish churn from re-rendering
/// anything but this button.
struct ItineraryButton: View {
    @EnvironmentObject var store: MemoryStore
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var presentedSheet: ItinerarySheet?

    private enum ItinerarySheet: Identifiable, Hashable {
        case paywall
        case planner
        var id: Self { self }
    }

    var body: some View {
        Button {
            presentedSheet = subscriptionManager.isSubscribed ? .planner : .paywall
        } label: {
            // wand.and.stars (the same icon used in the paywall this button
            // leads to) reads as "generate something" rather than "show a
            // map", and the teal tint matches that screen's branding so the
            // connection is visually obvious before you even tap it. Styled
            // to match BottomActionBar's own tab buttons (icon over caption)
            // since this button now lives in that same row.
            VStack(spacing: 3) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 21))
                Text("Itinerary")
                    .font(.caption2)
            }
            .foregroundStyle(.teal)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        // .sheet(item:) re-invokes its content closure whenever the item's
        // identity changes — unlike .sheet(isPresented:) with branching content,
        // which in practice didn't reliably re-render when isSubscribed flipped
        // true mid-presentation (purchase succeeded but the sheet stayed on the
        // paywall). Explicitly switching the item on subscribe is guaranteed to work.
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .planner:
                ItineraryPlannerView()
                    .environmentObject(store)
                    .environmentObject(locationManager)
                    .environmentObject(subscriptionManager)
            case .paywall:
                PaywallView()
                    .environmentObject(subscriptionManager)
            }
        }
        .onChange(of: subscriptionManager.isSubscribed) { _, subscribed in
            if subscribed && presentedSheet == .paywall {
                presentedSheet = .planner
            }
        }
    }
}

struct PaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "map.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.teal)
                    .padding(.top, 32)

                VStack(spacing: 8) {
                    Text("Itinerary Plus")
                        .font(.title2.bold())
                    Text("Discover a ready-to-go day out, wherever you are.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    featureRow(icon: "wand.and.stars", text: "A full day out — up to 10 stops, not a quick handful")
                    featureRow(icon: "slider.horizontal.3", text: "Pick a vibe — Relaxed, Cafe, Adventure, Foodie, Culture, or Mystery")
                    featureRow(icon: "gift.fill", text: "A Mystery Stop from an offbeat category, revealed on the day")
                    featureRow(icon: "point.topleft.down.curvedto.point.bottomright.up", text: "Real nearby places, closest good matches first")
                }
                .padding(.horizontal)

                Spacer()

                if let product = subscriptionManager.product {
                    Button {
                        Task {
                            isPurchasing = true
                            await subscriptionManager.purchase()
                            isPurchasing = false
                        }
                    } label: {
                        HStack {
                            if isPurchasing {
                                ProgressView().tint(.white)
                            } else {
                                Text("Subscribe — \(product.displayPrice)/month")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.teal, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                    }
                    .disabled(isPurchasing)
                    .padding(.horizontal)
                } else if subscriptionManager.hasAttemptedLoad {
                    Text("Subscription info isn't available right now. Check your connection and try again.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    ProgressView("Loading…")
                }

                Button("Restore Purchases") {
                    Task { await subscriptionManager.restorePurchases() }
                }
                .font(.footnote)
                .padding(.bottom, 8)

                if let error = subscriptionManager.purchaseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                if subscriptionManager.product == nil {
                    await subscriptionManager.loadProduct()
                }
            }
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.teal)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

struct ItineraryPlannerView: View {
    @EnvironmentObject var store: MemoryStore
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    @State private var vibe: ItineraryVibe = .relaxed
    @State private var maxDistanceKm: Double = 3
    @State private var travelMode: ItineraryTravelMode = .walking
    @State private var stops: [ItineraryStop] = []
    @State private var searchedRadiusKm: Double = 0
    @State private var isSearching = false
    @State private var showingEmptyResultAlert = false
    @State private var showingRouteMap = false
    /// Flips true if we've been waiting for a GPS fix for a while — gives the
    /// user an explicit, informed way out instead of a button that could
    /// otherwise stay disabled forever if a fix never arrives (weak signal,
    /// airplane mode, simulator with no location set, etc.).
    @State private var locationTimedOut = false
    @State private var userAcceptedFallbackLocation = false

    private static let fallbackLocationTimeout: Duration = .seconds(8)
    private static let fallbackCoordinate = CLLocationCoordinate2D(latitude: -27.4705, longitude: 153.0260)

    private var origin: CLLocationCoordinate2D {
        locationManager.currentLocation ?? Self.fallbackCoordinate
    }

    /// True once results come back searched wider than the distance the user
    /// actually picked — happens when that radius didn't have enough real
    /// places to fill the day. Compared with a small margin since the search
    /// radius is capped/rounded in ways that can put it fractionally above
    /// the requested km even when no expansion happened.
    private var wasRadiusExpanded: Bool {
        searchedRadiusKm > maxDistanceKm + 0.1
    }

    /// True while location access is authorized but we don't have a fix yet
    /// (e.g. right after launch, or a weak signal indoors) — distinct from
    /// isDenied. Generation is blocked in this state rather than silently
    /// searching around the hardcoded fallback coordinate, which previously
    /// meant a genuine GPS delay could search a city away from the user with
    /// no indication anything was wrong. Once locationTimedOut fires, the
    /// user can explicitly opt into the fallback instead of being stuck.
    private var isWaitingForLocation: Bool {
        locationManager.currentLocation == nil
            && !locationManager.isDenied
            && !(locationTimedOut && userAcceptedFallbackLocation)
    }

    private var canGenerate: Bool {
        !isSearching && !isWaitingForLocation
    }

    var body: some View {
        NavigationStack {
            Group {
                if stops.isEmpty {
                    setupView
                } else {
                    resultsView
                }
            }
            .navigationTitle("Plan a Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if !stops.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingRouteMap = true
                        } label: {
                            Image(systemName: "map")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Start Over") {
                            stops = []
                        }
                    }
                }
            }
            .task(id: locationManager.currentLocation == nil) {
                guard locationManager.currentLocation == nil, !locationManager.isDenied else { return }
                try? await Task.sleep(for: Self.fallbackLocationTimeout)
                guard !Task.isCancelled else { return }
                locationTimedOut = true
            }
            .sheet(isPresented: $showingRouteMap) {
                ItineraryRouteMapView(stops: stops, origin: origin, travelMode: travelMode)
            }
        }
    }

    private var setupView: some View {
        Form {
            if isWaitingForLocation, locationTimedOut {
                Section {
                    Label("Still no location after a few seconds — check you have a clear view of the sky, or Wi-Fi/cellular is on.", systemImage: "location.slash.fill")
                        .foregroundStyle(.orange)
                    Button("Search Near a Default Location Instead") {
                        userAcceptedFallbackLocation = true
                    }
                }
            } else if isWaitingForLocation {
                Section {
                    HStack {
                        ProgressView()
                        Text("Finding your location…")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Generating needs your current location to search nearby places — this should only take a moment. Make sure Location Services is on.")
                }
            } else if locationManager.currentLocation == nil {
                // Either denied outright, or the user explicitly accepted the
                // fallback after a timeout — either way, results are for a
                // default location, not where they actually are, and that
                // needs to stay visible rather than disappear the moment
                // generation becomes possible.
                Section {
                    if locationManager.isDenied {
                        Label("Location access is off, so this searches near a default location instead of where you actually are. Enable it in Settings for accurate results.", systemImage: "location.slash.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Label("Still couldn't get your location, so this is searching near a default location instead of where you actually are.", systemImage: "location.slash.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Pick a vibe") {
                Picker("Vibe", selection: $vibe) {
                    ForEach(ItineraryVibe.allCases) { vibe in
                        Label(vibe.rawValue, systemImage: vibe.icon).tag(vibe)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("How far") {
                Picker("Distance from you", selection: $maxDistanceKm) {
                    ForEach([1.0, 2.0, 3.0, 4.0, 5.0, 25.0], id: \.self) { km in
                        Text("\(Int(km)) km").tag(km)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Getting around") {
                Picker("Travel mode", selection: $travelMode) {
                    ForEach(ItineraryTravelMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button {
                    Task {
                        isSearching = true
                        let result = await ItineraryPlanner.discover(vibe: vibe, origin: origin, maxDistanceKm: maxDistanceKm)
                        stops = result.stops
                        searchedRadiusKm = result.searchedRadiusKm
                        isSearching = false
                        if stops.isEmpty {
                            showingEmptyResultAlert = true
                        }
                    }
                } label: {
                    HStack {
                        if isSearching {
                            ProgressView().tint(.white)
                        } else {
                            Text("Generate Itinerary")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                }
                .disabled(!canGenerate)
            } footer: {
                Text("Searches real nearby places live via Apple Maps — not your saved places.")
            }
        }
        .alert("No Places Found", isPresented: $showingEmptyResultAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing matched within \(Int(maxDistanceKm)) km for this vibe. Try a wider distance or a different vibe.")
        }
    }

    private var resultsView: some View {
        List {
            Section {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    ItineraryStopRow(stop: stop, index: index + 1, store: store, travelMode: travelMode)
                }
            } header: {
                if wasRadiusExpanded {
                    Text("\(vibe.rawValue) day · within \(Int(searchedRadiusKm)) km · \(travelMode.rawValue)")
                } else {
                    Text("\(vibe.rawValue) day · within \(Int(maxDistanceKm)) km · \(travelMode.rawValue)")
                }
            } footer: {
                if locationManager.currentLocation == nil {
                    Text("⚠️ Searched near a default location, not where you actually are — your device's real location wasn't available. Tap a place for details, or tap the directions icon to get there by \(travelMode.rawValue.lowercased()).")
                } else if wasRadiusExpanded {
                    Text("Only a few \(vibe.rawValue.lowercased()) spots were within \(Int(maxDistanceKm)) km, so the search expanded to \(Int(searchedRadiusKm)) km to fill out the day. Tap a place for details, or tap the directions icon to get there by \(travelMode.rawValue.lowercased()).")
                } else {
                    Text("Stops are ordered from your current location. Tap a place for details, or tap the directions icon to get there by \(travelMode.rawValue.lowercased()).")
                }
            }
        }
    }
}

private struct ItineraryStopRow: View {
    let stop: ItineraryStop
    let index: Int
    let store: MemoryStore
    let travelMode: ItineraryTravelMode

    @State private var mysteryRevealed = false
    @State private var showingDetail = false
    @State private var thumbnail: UIImage?

    private var isRevealed: Bool { !stop.isMysteryStop || mysteryRevealed }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if stop.isMysteryStop, !mysteryRevealed {
                    withAnimation { mysteryRevealed = true }
                } else {
                    showingDetail = true
                }
            } label: {
                HStack(spacing: 12) {
                    stepNumber

                    if isRevealed, let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if isRevealed {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(stop.place.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if stop.isMysteryStop {
                                    Image(systemName: "gift.fill")
                                        .font(.caption)
                                        .foregroundStyle(.purple)
                                }
                            }
                            Text(stop.place.category.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mystery Stop")
                                .font(.headline)
                                .foregroundStyle(.purple)
                            Text("Tap to reveal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if isRevealed {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            if isRevealed {
                Button {
                    openDirections()
                } label: {
                    Image(systemName: travelMode.icon)
                        .font(.title3)
                        .foregroundStyle(.teal)
                        .frame(width: 36, height: 36)
                        .background(.teal.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingDetail) {
            DiscoveredPlaceDetailSheet(place: stop.place, travelMode: travelMode)
                .environmentObject(store)
        }
        .task {
            guard thumbnail == nil, let website = stop.place.website, let url = URL(string: website) else { return }
            thumbnail = await LinkPreviewImageLoader.shared.image(for: url)
        }
    }

    private func openDirections() {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: stop.place.coordinate))
        mapItem.name = stop.place.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: travelMode.launchDirectionsModeKey])
    }

    private var stepNumber: some View {
        ZStack {
            Circle()
                .fill(stop.isMysteryStop ? Color.purple.opacity(0.15) : stop.place.category.color.opacity(0.15))
                .frame(width: 32, height: 32)
            if isRevealed {
                Text("\(index)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(stop.isMysteryStop ? .purple : stop.place.category.color)
            } else {
                Image(systemName: "questionmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)
            }
        }
    }
}

/// Detail sheet for a place found via live search — not a saved TravelMemory,
/// so this shows only what MapKit's listing provides, plus a way to actually
/// save it into the user's own places.
private struct DiscoveredPlaceDetailSheet: View {
    let place: DiscoveredPlace
    let travelMode: ItineraryTravelMode
    @EnvironmentObject var store: MemoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var didSave = false
    @State private var previewCameraPosition: MapCameraPosition
    // MapKit itself exposes no business photos, but many sites publish their
    // own preview image — this pulls one from the place's website, when it
    // has one, via the same link-preview mechanism Messages/Safari use. When
    // there's no website, or the site has no preview image, this stays nil
    // and the map below is the only visual, same as before.
    @State private var heroImage: UIImage?
    @State private var heroImageLoadAttempted = false

    private var isHeroSectionShown: Bool {
        heroImage != nil || (place.website != nil && !heroImageLoadAttempted)
    }

    init(place: DiscoveredPlace, travelMode: ItineraryTravelMode) {
        self.place = place
        self.travelMode = travelMode
        _previewCameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: place.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let heroImage {
                    Section {
                        Image(uiImage: heroImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 220)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .listRowInsets(EdgeInsets())
                    }
                } else if let website = place.website, let url = URL(string: website), !heroImageLoadAttempted {
                    Section {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .listRowInsets(EdgeInsets())
                    }
                    .task {
                        heroImage = await LinkPreviewImageLoader.shared.image(for: url)
                        heroImageLoadAttempted = true
                    }
                }

                Section {
                    Map(position: $previewCameraPosition) {
                        Marker(place.name, coordinate: place.coordinate)
                    }
                    .frame(height: isHeroSectionShown ? 120 : 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    HStack {
                        Image(systemName: place.category.icon)
                            .foregroundStyle(place.category.color)
                        Text(place.category.rawValue)
                            .foregroundStyle(.secondary)
                    }
                    if let address = place.address {
                        Label(address, systemImage: "mappin.and.ellipse")
                    }
                    if let phoneNumber = place.phoneNumber, let url = URL(string: "tel:\(phoneNumber.filter { $0.isNumber || $0 == "+" })") {
                        Link(destination: url) {
                            Label(phoneNumber, systemImage: "phone.fill")
                        }
                    }
                    if let website = place.website, let url = URL(string: website) {
                        Link(destination: url) {
                            Label(website, systemImage: "globe")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                Section {
                    Button {
                        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
                        mapItem.name = place.name
                        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: travelMode.launchDirectionsModeKey])
                    } label: {
                        Label("Get Directions", systemImage: travelMode.icon)
                    }

                    Button {
                        openReviewsSearch()
                    } label: {
                        Label("Find Reviews", systemImage: "star.bubble.fill")
                    }

                    Button {
                        store.add(TravelMemory(
                            name: place.name,
                            latitude: place.coordinate.latitude,
                            longitude: place.coordinate.longitude,
                            category: place.category,
                            address: place.address,
                            website: place.website,
                            phoneNumber: place.phoneNumber
                        ))
                        didSave = true
                    } label: {
                        Label(didSave ? "Saved to My Places" : "Save to My Places", systemImage: didSave ? "checkmark.circle.fill" : "plus.circle")
                    }
                    .disabled(didSave)
                } footer: {
                    Text("MapKit doesn't provide reviews directly, so this opens a TripAdvisor search for this place instead.")
                }
            }
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    /// MapKit's public API doesn't provide reviews, so this opens a TripAdvisor
    /// search for the place instead — same honest-workaround pattern already
    /// used for saved places in MemoryDetailView.
    private func openReviewsSearch() {
        var query = place.name
        if let address = place.address, !address.isEmpty {
            query += " \(address)"
        }
        var components = URLComponents(string: "https://www.tripadvisor.com/Search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }
}
