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
            // A plain "map" icon read as "show the map" — easy to mistake for
            // the Map tab itself. wand.and.stars (the same icon used in the
            // paywall this button leads to) reads as "generate something"
            // instead, and the teal tint matches that screen's branding so
            // the connection is visually obvious before you even tap it.
            Label("Plan a Day", systemImage: "wand.and.stars")
        }
        .tint(.teal)
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
    @State private var isSearching = false
    @State private var showingEmptyResultAlert = false

    private var origin: CLLocationCoordinate2D {
        locationManager.currentLocation ?? CLLocationCoordinate2D(latitude: -27.4705, longitude: 153.0260)
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
                        Button("Start Over") {
                            stops = []
                        }
                    }
                }
            }
        }
    }

    private var setupView: some View {
        Form {
            if locationManager.isDenied {
                Section {
                    Label("Location access is off, so this searches near a default location instead of where you actually are. Enable it in Settings for accurate results.", systemImage: "location.slash.fill")
                        .foregroundStyle(.orange)
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
                        stops = await ItineraryPlanner.discover(vibe: vibe, origin: origin, maxDistanceKm: maxDistanceKm)
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
                .disabled(isSearching)
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
                Text("\(vibe.rawValue) day · within \(Int(maxDistanceKm)) km · \(travelMode.rawValue)")
            } footer: {
                Text("Stops are ordered from your current location. Tap a place for details, or tap the directions icon to get there by \(travelMode.rawValue.lowercased()).")
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
