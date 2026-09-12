//
//  MemoryListView.swift
//  Comebackone day 1.2
//

import SwiftUI
import StoreKit

struct MemoryListView: View {
    @EnvironmentObject var store: MemoryStore
    @EnvironmentObject var eventStore: EventStore
    @Environment(\.bottomBarReservedHeight) private var bottomBarReservedHeight
    @State private var selectedMemory: TravelMemory?
    @State private var showingEvents = false
    @State private var searchText = ""
    @State private var filterCategory: Category?
    @State private var filterCountry: String?
    @State private var filterTrip: String?
    @State private var filterStatus: VisitStatus?

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
                    .safeAreaInset(edge: .bottom) {
                        // A safeAreaInset reserved at the TabView level
                        // (ContentView) does not reach this List for scroll-
                        // content-inset purposes — the last row stays
                        // permanently covered by BottomActionBar (and the ad
                        // banner) until this List reserves the room itself.
                        Color.clear.frame(height: bottomBarReservedHeight)
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
                        showingEvents = true
                    } label: {
                        Image(systemName: "ticket")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    SettingsButton()
                }
            }
            .sheet(item: $selectedMemory) { memory in
                MemoryDetailView(memoryID: memory.id)
            }
            .sheet(isPresented: $showingEvents) {
                EventListView()
                    .environmentObject(eventStore)
            }
        }
    }

    private func delete(_ offsets: IndexSet, from sectionMemories: [TravelMemory]) {
        for index in offsets {
            store.delete(sectionMemories[index])
        }
    }
}

/// Isolated in its own view so subscribing to LocationManager (which republishes
/// on every GPS update once nudges are on) only invalidates this tiny button,
/// not the whole Places list — that coupling was causing the list to reset its
/// scroll position mid-scroll whenever a location update landed.
private struct SettingsButton: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var adsManager: AdsManager
    @EnvironmentObject var journalLockManager: JournalLockManager
    @EnvironmentObject var journalReminderManager: JournalReminderManager
    @EnvironmentObject var eventReminderManager: EventReminderManager
    @State private var showingSettings = false

    var body: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet()
                .environmentObject(locationManager)
                .environmentObject(adsManager)
                .environmentObject(journalLockManager)
                .environmentObject(journalReminderManager)
                .environmentObject(eventReminderManager)
        }
    }
}

private struct SettingsSheet: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var adsManager: AdsManager
    @EnvironmentObject var journalLockManager: JournalLockManager
    @EnvironmentObject var journalReminderManager: JournalReminderManager
    @EnvironmentObject var eventReminderManager: EventReminderManager
    @Environment(\.dismiss) private var dismiss

    /// DatePicker needs a Date; the manager stores hour/minute as
    /// DateComponents (there's no meaningful day/month/year for a daily
    /// recurring reminder). Bridges between the two, anchored to today.
    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: journalReminderManager.reminderTime) ?? Date() },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                journalReminderManager.reminderTime = components
            }
        )
    }

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

                Section {
                    Toggle("Lock Journal with Face ID", isOn: $journalLockManager.isLockEnabled)
                } footer: {
                    Text("Require Face ID or your passcode to open the Journal tab.")
                }

                Section {
                    Toggle("Daily Reminder", isOn: Binding(
                        get: { journalReminderManager.isReminderEnabled },
                        set: { newValue in
                            if newValue {
                                journalReminderManager.enable()
                            } else {
                                journalReminderManager.disable()
                            }
                        }
                    ))
                    if journalReminderManager.isReminderEnabled {
                        DatePicker("Remind me at", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Journal")
                } footer: {
                    Text("A daily notification nudging you to write in your journal.")
                }

                Section {
                    Toggle("Notify Me Before Events", isOn: Binding(
                        get: { eventReminderManager.upcomingNudgesEnabled },
                        set: { newValue in
                            if newValue {
                                eventReminderManager.enableUpcomingNudges()
                            } else {
                                eventReminderManager.disableUpcomingNudges()
                            }
                        }
                    ))
                    if eventReminderManager.upcomingNudgesEnabled {
                        Picker("Remind Me", selection: $eventReminderManager.upcomingLeadTime) {
                            ForEach(EventReminderLeadTime.allCases) { leadTime in
                                Text(leadTime.label).tag(leadTime)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Toggle("Remind Me a Year Later", isOn: Binding(
                        get: { eventReminderManager.memoryNudgesEnabled },
                        set: { newValue in
                            if newValue {
                                eventReminderManager.enableMemoryNudges()
                            } else {
                                eventReminderManager.disableMemoryNudges()
                            }
                        }
                    ))
                } header: {
                    Text("Events")
                } footer: {
                    Text("Get a notification before an upcoming event, and a reminder a year after an event you attended.")
                }

                Section {
                    if adsManager.isAdRemoved {
                        Label("Ads removed", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else if let product = adsManager.product {
                        Button {
                            Task { await adsManager.purchase() }
                        } label: {
                            HStack {
                                Text("Remove Ads")
                                Spacer()
                                Text(product.displayPrice)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if adsManager.hasAttemptedLoad {
                        Text("Remove Ads is unavailable right now.")
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }

                    Button("Restore Purchases") {
                        Task { await adsManager.restorePurchases() }
                    }

                    if let error = adsManager.purchaseError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Ads")
                } footer: {
                    Text("A one-time purchase that removes ads from Come Back One Day, forever.")
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
