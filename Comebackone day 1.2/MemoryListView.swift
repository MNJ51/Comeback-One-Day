//
//  MemoryListView.swift
//  Comebackone day 1.2
//

import SwiftUI

struct MemoryListView: View {
    @EnvironmentObject var store: MemoryStore
    @EnvironmentObject var locationManager: LocationManager
    @State private var selectedMemory: TravelMemory?
    @State private var searchText = ""
    @State private var filterCategory: Category?
    @State private var filterCountry: String?
    @State private var filterTrip: String?
    @State private var filterStatus: VisitStatus?
    @State private var showingSettings = false

    private static let noTripSectionTitle = "No Trip"

    /// Every distinct country found in the saved places' addresses, for the filter menu.
    private var availableCountries: [String] {
        let countries = store.memories.compactMap(\.country)
        return Array(Set(countries)).sorted()
    }

    /// Every distinct trip name in use, for the filter menu.
    private var availableTrips: [String] {
        let trips = store.memories.compactMap(\.tripName)
        return Array(Set(trips)).sorted()
    }

    private var visibleMemories: [TravelMemory] {
        var result = store.memories

        if let filterCategory {
            result = result.filter { $0.category == filterCategory }
        }

        if let filterCountry {
            result = result.filter { $0.country == filterCountry }
        }

        if let filterTrip {
            result = result.filter { $0.tripName == filterTrip }
        }

        if let filterStatus {
            result = result.filter { $0.visitStatus == filterStatus }
        }

        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || ($0.address?.localizedCaseInsensitiveContains(query) ?? false)
                    || $0.notes.localizedCaseInsensitiveContains(query)
            }
        }

        return result.sorted {
            ($0.dateVisited ?? $0.dateAdded) > ($1.dateVisited ?? $1.dateAdded)
        }
    }

    /// Visible places grouped into trip/city collections, untagged places last.
    private var groupedByTrip: [(trip: String, memories: [TravelMemory])] {
        let groups = Dictionary(grouping: visibleMemories) { $0.tripName ?? Self.noTripSectionTitle }
        return groups.keys.sorted { lhs, rhs in
            if lhs == Self.noTripSectionTitle { return false }
            if rhs == Self.noTripSectionTitle { return true }
            return lhs < rhs
        }.map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.memories.isEmpty {
                    ContentUnavailableView(
                        "No Places Yet",
                        systemImage: "mappin.slash",
                        description: Text("Add your first memory from the Map tab.")
                    )
                } else if visibleMemories.isEmpty {
                    ContentUnavailableView.search
                } else {
                    List {
                        ForEach(groupedByTrip, id: \.trip) { group in
                            Section(group.trip) {
                                ForEach(group.memories) { memory in
                                    Button(action: {
                                        selectedMemory = memory
                                    }) {
                                        MemoryRow(memory: memory)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .onDelete { offsets in delete(offsets, from: group.memories) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("My Places")
            .searchable(text: $searchText, prompt: "Search places, addresses, notes")
            .refreshable {
                await store.syncNow()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Category", selection: $filterCategory) {
                            Text("All Categories").tag(Category?.none)
                            ForEach(Category.allCases) { cat in
                                Label(cat.rawValue, systemImage: cat.icon).tag(Category?.some(cat))
                            }
                        }

                        if !availableCountries.isEmpty {
                            Picker("Country", selection: $filterCountry) {
                                Text("All Countries").tag(String?.none)
                                ForEach(availableCountries, id: \.self) { country in
                                    Text(country).tag(String?.some(country))
                                }
                            }
                        }

                        if !availableTrips.isEmpty {
                            Picker("Trip", selection: $filterTrip) {
                                Text("All Trips").tag(String?.none)
                                ForEach(availableTrips, id: \.self) { trip in
                                    Text(trip).tag(String?.some(trip))
                                }
                            }
                        }

                        Picker("Status", selection: $filterStatus) {
                            Text("All Places").tag(VisitStatus?.none)
                            ForEach(VisitStatus.allCases) { status in
                                Text(status.rawValue).tag(VisitStatus?.some(status))
                            }
                        }
                    } label: {
                        Image(systemName: (filterCategory == nil && filterCountry == nil && filterTrip == nil && filterStatus == nil)
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(item: $selectedMemory) { memory in
                MemoryDetailView(memoryID: memory.id)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsSheet()
                    .environmentObject(locationManager)
            }
        }
    }

    private func delete(_ offsets: IndexSet, from sectionMemories: [TravelMemory]) {
        for index in offsets {
            store.delete(sectionMemories[index])
        }
    }
}

private struct SettingsSheet: View {
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Notify me near wishlist places", isOn: Binding(
                        get: { locationManager.proximityNudgesEnabled },
                        set: { newValue in
                            if newValue {
                                locationManager.enableProximityNudges()
                            } else {
                                locationManager.disableProximityNudges()
                            }
                        }
                    ))
                } footer: {
                    Text("Get a notification when you're near a place on your Want to Go list — even when the app isn't open. This needs Always location access and notification permission, both requested when you turn it on.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct MemoryRow: View {
    let memory: TravelMemory

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnail = PhotoStore.thumbnail(for: memory.coverPhotoFilename, maxDimension: 50) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: memory.category.icon)
                    .font(.title3)
                    .foregroundStyle(memory.category.color)
                    .frame(width: 50, height: 50)
                    .background(memory.category.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(memory.name)
                    .font(.headline)

                HStack(spacing: 6) {
                    Text(memory.category.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(memory.category.color.opacity(0.15))
                        .foregroundStyle(memory.category.color)
                        .clipShape(Capsule())

                    if memory.visitStatus == .wantToGo {
                        Text("Want to Go")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.yellow.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    } else if let dateVisited = memory.dateVisited {
                        Text(dateVisited, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let country = memory.country {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.caption2)
                        Text(country)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                StarRatingLabel(rating: memory.rating, font: .caption2)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        // Without this, taps in the empty trailing space (after the text, before
        // the row's edge) don't register — only taps on the actual rendered
        // content (image, text) count as a hit, since SwiftUI's default hit
        // testing skips fully transparent regions like a bare Spacer().
        .contentShape(Rectangle())
    }
}
