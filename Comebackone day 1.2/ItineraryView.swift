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
    @State private var showingItinerary = false

    var body: some View {
        Button {
            showingItinerary = true
        } label: {
            Image(systemName: "map")
        }
        .sheet(isPresented: $showingItinerary) {
            if subscriptionManager.isSubscribed {
                ItineraryPlannerView()
                    .environmentObject(store)
                    .environmentObject(locationManager)
                    .environmentObject(subscriptionManager)
            } else {
                PaywallView()
                    .environmentObject(subscriptionManager)
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
            .onChange(of: subscriptionManager.isSubscribed) { _, subscribed in
                if subscribed { dismiss() }
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
    @State private var stops: [ItineraryStop] = []
    @State private var hasGenerated = false

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

            Section {
                Button {
                    stops = ItineraryPlanner.generate(from: store.memories, vibe: vibe, origin: origin)
                    hasGenerated = true
                } label: {
                    Text("Generate Itinerary")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .disabled(store.memories.isEmpty)
            } footer: {
                if hasGenerated && stops.isEmpty {
                    Text("Couldn't find enough saved places nearby to build a day out of.")
                } else if store.memories.isEmpty {
                    Text("Save a few places first, then come back to plan a day.")
                }
            }
        }
    }

    private var resultsView: some View {
        List {
            Section {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    ItineraryStopRow(stop: stop, index: index + 1, store: store)
                }
            } header: {
                Text(vibe.rawValue + " day")
            } footer: {
                Text("Stops are ordered from your current location. Tap a place to open it, or get directions to it directly.")
            }
        }
    }
}

private struct ItineraryStopRow: View {
    let stop: ItineraryStop
    let index: Int
    let store: MemoryStore

    @State private var mysteryRevealed = false
    @State private var showingDetail = false

    private var isRevealed: Bool { !stop.isMysteryStop || mysteryRevealed }

    var body: some View {
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
        .sheet(isPresented: $showingDetail) {
            MemoryDetailView(memoryID: stop.memory.id)
                .environmentObject(store)
        }
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
