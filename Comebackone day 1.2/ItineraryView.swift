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
            Image(systemName: "map")
        }
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
                    Text("Turn your saved places into a ready-to-go day out.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    featureRow(icon: "wand.and.stars", text: "Auto-generated day itineraries from your saved places")
                    featureRow(icon: "slider.horizontal.3", text: "Pick a vibe — Relaxed, Adventure, Foodie, or Culture")
                    featureRow(icon: "gift.fill", text: "A Mystery Stop pulled from your wishlist, revealed on the day")
                    featureRow(icon: "point.topleft.down.curvedto.point.bottomright.up", text: "Stops ordered into a sensible route from where you are")
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
    @State private var glutenFreeOnly = false
    @State private var topRatedRestaurantsOnly = false
    @State private var maxDistanceKm: Double = 3
    @State private var travelMode: ItineraryTravelMode = .walking
    @State private var stops: [ItineraryStop] = []
    @State private var showingEmptyResultAlert = false

    private var origin: CLLocationCoordinate2D {
        locationManager.currentLocation ?? store.memories.first?.coordinate
            ?? CLLocationCoordinate2D(latitude: -27.4705, longitude: 153.0260)
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
                Toggle("Gluten Free Restaurants Only", isOn: $glutenFreeOnly)
            } footer: {
                Text("Only include restaurants, cafes, bars, and markets marked as having gluten-free options.")
            }

            Section {
                Toggle("Top-Rated Restaurants Only", isOn: $topRatedRestaurantsOnly)
            } footer: {
                Text("Only include restaurants rated 4 stars or higher — the closest we can do to \"4.5+\" since ratings are whole stars.")
            }

            Section {
                Button {
                    stops = ItineraryPlanner.generate(
                        from: store.memories,
                        vibe: vibe,
                        origin: origin,
                        maxDistanceKm: maxDistanceKm,
                        glutenFreeOnly: glutenFreeOnly,
                        topRatedRestaurantsOnly: topRatedRestaurantsOnly
                    )
                    if stops.isEmpty {
                        showingEmptyResultAlert = true
                    }
                } label: {
                    Text("Generate Itinerary")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .disabled(store.memories.isEmpty)
            } footer: {
                Text("Only searches places you've already saved in the app — not a general directory of nearby businesses.")
            }
        }
        .alert("No Places Found", isPresented: $showingEmptyResultAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("None of your saved places matched — within \(Int(maxDistanceKm)) km, this vibe, and your filters. Try a wider distance or a different vibe. Remember: this only searches places you've saved, not all nearby businesses.")
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
                Text("Stops are ordered from your current location. Tap a place to open it, or tap the directions icon to get there by \(travelMode.rawValue.lowercased()).")
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

                    if isRevealed {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(stop.memory.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if stop.isMysteryStop {
                                    Image(systemName: "gift.fill")
                                        .font(.caption)
                                        .foregroundStyle(.purple)
                                }
                            }
                            Text(stop.memory.category.rawValue)
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
            MemoryDetailView(memoryID: stop.memory.id)
                .environmentObject(store)
        }
    }

    private func openDirections() {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: stop.memory.coordinate))
        mapItem.name = stop.memory.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: travelMode.launchDirectionsModeKey])
    }

    private var stepNumber: some View {
        ZStack {
            Circle()
                .fill(stop.isMysteryStop ? Color.purple.opacity(0.15) : stop.memory.category.color.opacity(0.15))
                .frame(width: 32, height: 32)
            if isRevealed {
                Text("\(index)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(stop.isMysteryStop ? .purple : stop.memory.category.color)
            } else {
                Image(systemName: "questionmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)
            }
        }
    }
}
