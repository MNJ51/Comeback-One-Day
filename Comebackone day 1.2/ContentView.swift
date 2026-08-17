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
}

struct ContentView: View {
    @StateObject private var store = MemoryStore()
    @StateObject private var locationManager = LocationManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingImport: TravelMemory?
    @State private var selectedTab: AppTab = .map
    @State private var showingAddMemory = false
    @State private var showingQuickCamera = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                MapTabView()
                    .tag(AppTab.map)
                    .toolbar(.hidden, for: .tabBar)

                MemoryListView()
                    .tag(AppTab.places)
                    .toolbar(.hidden, for: .tabBar)
            }
            .safeAreaInset(edge: .bottom) {
                // Reserves room so list content doesn't sit behind the floating
                // bar below; the map still goes edge-to-edge under it as before.
                Color.clear.frame(height: BottomActionBar.height)
            }

            BottomActionBar(
                selectedTab: $selectedTab,
                showingAddMemory: $showingAddMemory,
                showingQuickCamera: $showingQuickCamera
            )
        }
        .environmentObject(store)
        .environmentObject(locationManager)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await store.syncNow()
                }
            }
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

/// The single floating bar along the bottom: Map/Places tab switching plus the
/// Camera and Add actions, all in one line instead of stacked in two rows.
struct BottomActionBar: View {
    @Binding var selectedTab: AppTab
    @Binding var showingAddMemory: Bool
    @Binding var showingQuickCamera: Bool

    static let height: CGFloat = 92

    var body: some View {
        HStack(spacing: 0) {
            tabButton(icon: "map.fill", label: "Map", isSelected: selectedTab == .map) {
                selectedTab = .map
            }

            tabButton(icon: "list.bullet", label: "Places", isSelected: selectedTab == .places) {
                selectedTab = .places
            }

            if CameraView.isAvailable {
                largeButton(icon: "camera.circle.fill", tint: .green) {
                    showingQuickCamera = true
                }
            }

            largeButton(icon: "plus.circle.fill", tint: .blue) {
                showingAddMemory = true
            }
        }
        .padding(.vertical, 8)
        .background(.thickMaterial, in: Capsule())
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
                .shadow(radius: 3)
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

            VStack {
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
                .background(isSelected ? AnyShapeStyle(color) : AnyShapeStyle(.thickMaterial), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
                .shadow(radius: 2)
        }
        .buttonStyle(.plain)
    }
}

struct MemoryPin: View {
    let memory: TravelMemory

    var body: some View {
        Group {
            if let thumbnail = PhotoStore.thumbnail(for: memory.coverPhotoFilename, maxDimension: 40) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(memory.category.color, lineWidth: 3))
                    .shadow(radius: 3)
            } else {
                Image(systemName: "mappin.circle.fill")
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
