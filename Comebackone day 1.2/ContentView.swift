//
//  ContentView.swift
//  Comebackone day 1.2
//
//  Created by Michael Jee on 5/1/2026.
//

import SwiftUI
import MapKit

enum AppTab {
    case map
    case places
    case journal
}

/// Reports BottomActionBar's real rendered height, since it varies with
/// Dynamic Type and safe-area insets — `BottomActionBar.height` is only a
/// starting estimate for the very first layout pass, not a hard truth. Feeds
/// `ContentView.bottomReservedHeight`, which sizes the reservation each tab's
/// list content scrolls above; if the reservation ever falls short of the
/// bar's true height, the last bit of content gets permanently hidden behind
/// it with no way to scroll further to reveal it.
private struct BottomActionBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = BottomActionBar.height
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// The real, measured height each tab's own list content should reserve at
/// its bottom so the last row can fully scroll clear of the floating
/// BottomActionBar (and ad banner, when shown). A `.safeAreaInset` added at
/// the TabView level does *not* propagate into a page's own List for scroll-
/// content-inset purposes — confirmed empirically, a List only actually
/// gains the extra scrollable room when it adds this inset on itself — so
/// each tab's list reads this via the environment and applies its own
/// `.safeAreaInset(edge: .bottom)`.
private struct BottomBarReservedHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = BottomActionBar.height
}

extension EnvironmentValues {
    var bottomBarReservedHeight: CGFloat {
        get { self[BottomBarReservedHeightKey.self] }
        set { self[BottomBarReservedHeightKey.self] = newValue }
    }
}

struct ContentView: View {
    @StateObject private var store = MemoryStore()
    @StateObject private var journalStore = JournalStore()
    @StateObject private var eventStore = EventStore()
    @StateObject private var journalAppearanceStore = JournalAppearanceStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var subscriptionManager = SubscriptionManager()
    @StateObject private var adsManager = AdsManager()
    @StateObject private var journalLockManager = JournalLockManager()
    @StateObject private var journalReminderManager = JournalReminderManager()
    @StateObject private var eventReminderManager = EventReminderManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingImport: TravelMemory?
    @State private var selectedTab: AppTab = .map
    @State private var showingAddMemory = false
    @State private var showingQuickCamera = false
    /// Starts at the static estimate, then self-corrects to the bar's real
    /// rendered height (see BottomActionBarHeightKey) once the first layout
    /// pass reports it.
    @State private var bottomReservedHeight: CGFloat = BottomActionBar.height

    /// Ads only show on Map/Places (not Journal), and never once purchased away.
    /// Computed here — rather than nesting a safeAreaInset inside each tab's own
    /// view — because a safeAreaInset added from *inside* a TabView page gets
    /// clipped by the page's own container and never actually paints on screen,
    /// even though it lays out with a correct, non-hidden frame.
    private var showsAdBanner: Bool {
        !adsManager.isAdRemoved && (selectedTab == .map || selectedTab == .places)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                MapTabView()
                    .tag(AppTab.map)
                    .toolbar(.hidden, for: .tabBar)

                MemoryListView()
                    .tag(AppTab.places)
                    .toolbar(.hidden, for: .tabBar)

                JournalLockGateView {
                    JournalListView()
                }
                .tag(AppTab.journal)
                .toolbar(.hidden, for: .tabBar)
            }
            .safeAreaInset(edge: .bottom) {
                // Reserves room so list content doesn't sit behind the floating
                // bar (and ad banner) below; the map still goes edge-to-edge
                // under it as before.
                Color.clear.frame(height: bottomReservedHeight)
            }

            VStack(spacing: 0) {
                if showsAdBanner {
                    AdBanner()
                }

                BottomActionBar(
                    selectedTab: $selectedTab,
                    showingAddMemory: $showingAddMemory,
                    showingQuickCamera: $showingQuickCamera
                )
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: BottomActionBarHeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(BottomActionBarHeightKey.self) { bottomReservedHeight = $0 }
        }
        .environmentObject(store)
        .environmentObject(journalStore)
        .environmentObject(eventStore)
        .environmentObject(journalAppearanceStore)
        .environmentObject(locationManager)
        .environmentObject(subscriptionManager)
        .environmentObject(adsManager)
        .environmentObject(journalLockManager)
        .environmentObject(journalReminderManager)
        .environmentObject(eventReminderManager)
        .environment(\.bottomBarReservedHeight, bottomReservedHeight)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await store.syncNow()
                    await journalStore.syncNow()
                    await eventStore.syncNow()
                }
            }
        }
        .task {
            locationManager.updateMonitoredRegions(for: store.memories)
            eventReminderManager.updateSchedule(for: eventStore.events)
        }
        .onChange(of: store.memories) { _, newMemories in
            locationManager.updateMonitoredRegions(for: newMemories)
        }
        .onChange(of: eventStore.events) { _, newEvents in
            eventReminderManager.updateSchedule(for: newEvents)
        }
        .onOpenURL { url in
            if let imported = TravelMemory(shareURL: url) {
                pendingImport = imported
            }
        }
        .alert("Add this place?", isPresented: Binding(
            get: { pendingImport != nil },
            set: { if !$0 { pendingImport = nil } }
        ), presenting: pendingImport) { place in
            Button("Add") {
                store.add(place)
                pendingImport = nil
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: { place in
            Text("Add “\(place.name)” to your places?")
        }
        .sheet(isPresented: $showingAddMemory) {
            AddMemoryView()
                .environmentObject(store)
                .environmentObject(locationManager)
        }
        .sheet(isPresented: $showingQuickCamera) {
            QuickCameraView()
                .environmentObject(store)
                .environmentObject(locationManager)
        }
    }
}

/// The floating bar along the bottom, two rows: Map/Places/Journal/Itinerary
/// tab-style switching on top, Camera and Add actions underneath. Itinerary
/// lives here (not buried in the Places toolbar) so "plan a day" is as
/// discoverable as the other core sections from the very first screen.
struct BottomActionBar: View {
    @Binding var selectedTab: AppTab
    @Binding var showingAddMemory: Bool
    @Binding var showingQuickCamera: Bool

    static let height: CGFloat = 132

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                tabButton(icon: "map.fill", label: "Map", isSelected: selectedTab == .map) {
                    selectedTab = .map
                }

                tabButton(icon: "list.bullet", label: "Places", isSelected: selectedTab == .places) {
                    selectedTab = .places
                }

                tabButton(icon: "book.closed.fill", label: "Journal", isSelected: selectedTab == .journal) {
                    selectedTab = .journal
                }

                ItineraryButton()

                FindButton()
            }

            HStack(spacing: 0) {
                if CameraView.isAvailable {
                    largeButton(icon: "camera.circle.fill", tint: .green) {
                        showingQuickCamera = true
                    }
                }

                largeButton(icon: "plus.circle.fill", tint: .blue) {
                    showingAddMemory = true
                }
            }
        }
        .padding(.vertical, 10)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 26))
        .shadow(radius: 4)
        .padding(.horizontal)
    }

    /// Map/Places: compact icon-over-label, matching a standard tab item.
    @ViewBuilder
    private func tabButton(icon: String, label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 21))
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// Camera/Add: the original large, colorful circular icons, just moved
    /// into this same row instead of floating separately above it.
    @ViewBuilder
    private func largeButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct MapTabView: View {
    @EnvironmentObject var store: MemoryStore
    @EnvironmentObject var locationManager: LocationManager

    // Start on the user's current location; fall back to a default region
    // while location is loading or if permission is denied.
    @State private var cameraPosition = MapCameraPosition.userLocation(
        fallback: .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: -27.4705, longitude: 153.0260),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        )
    )

    @State private var selectedMemory: TravelMemory?
    @State private var filterCategory: Category?

    private var filteredMemories: [TravelMemory] {
        guard let filterCategory else { return store.memories }
        return store.memories.filter { $0.category == filterCategory }
    }

    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                UserAnnotation()

                ForEach(filteredMemories) { memory in
                    Annotation(memory.name, coordinate: memory.coordinate) {
                        MemoryPin(memory: memory)
                            .onTapGesture {
                                selectedMemory = memory
                            }
                    }
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 8) {
                if let flashback = store.memories.first(where: { $0.isOnThisDay() }) {
                    OnThisDayBanner(memory: flashback) {
                        selectedMemory = flashback
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "All", color: .gray, isSelected: filterCategory == nil) {
                            filterCategory = nil
                        }
                        ForEach(Category.allCases) { cat in
                            FilterChip(title: cat.rawValue, color: cat.color, isSelected: filterCategory == cat) {
                                filterCategory = filterCategory == cat ? nil : cat
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 8)

                Spacer()
            }
        }
        .sheet(item: $selectedMemory) { memory in
            MemoryDetailView(memoryID: memory.id)
        }
    }
}

struct FilterChip: View {
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? AnyShapeStyle(color) : AnyShapeStyle(.ultraThickMaterial), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
                .shadow(radius: 2)
        }
        .buttonStyle(.plain)
    }
}

/// "You saved this N years ago today" flashback, tappable to reopen the place.
struct OnThisDayBanner: View {
    let memory: TravelMemory
    let action: () -> Void

    private var subtitle: String {
        guard let years = memory.yearsAgo(), years > 0 else { return "On this day" }
        return years == 1 ? "1 year ago today" : "\(years) years ago today"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let thumbnail = PhotoStore.thumbnail(for: memory.coverPhotoFilename, maxDimension: 40) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "sparkles")
                        .foregroundStyle(memory.category.color)
                        .frame(width: 40, height: 40)
                        .background(memory.category.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(memory.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 2)
        }
        .buttonStyle(.plain)
    }
}

struct MemoryPin: View {
    let memory: TravelMemory

    private var isWishlist: Bool { memory.visitStatus == .wantToGo }

    var body: some View {
        Group {
            if let thumbnail = PhotoStore.thumbnail(for: memory.coverPhotoFilename, maxDimension: 40) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(
                            memory.category.color,
                            style: StrokeStyle(lineWidth: 3, dash: isWishlist ? [4, 3] : [])
                        )
                    )
                    .shadow(radius: 3)
            } else {
                // Outline pin for a wishlist place not yet visited, filled once it's been to.
                Image(systemName: isWishlist ? "mappin.circle" : "mappin.circle.fill")
                    .foregroundStyle(memory.category.color)
                    .font(.title2)
            }
        }
        // A second ring around the category-color one, marking a place someone
        // else shared with you rather than one you added yourself.
        .overlay {
            if memory.isReceivedFromShare {
                Circle()
                    .stroke(Color.yellow, lineWidth: 3)
                    .padding(-5)
            }
        }
    }
}

#Preview {
    ContentView()
}
