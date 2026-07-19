//
//  ContentView.swift
//  Comebackone day 1.1
//
//  Created by Michael Jee on 5/1/2026.
//

import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var store = MemoryStore()
    @StateObject private var locationManager = LocationManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingImport: TravelMemory?

    var body: some View {
        TabView {
            MapTabView()
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }

            MemoryListView()
                .tabItem {
                    Label("Places", systemImage: "list.bullet")
                }
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

    @State private var showingAddMemory = false
    @State private var showingQuickCamera = false
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
                HStack {
                    Spacer()

                    if CameraView.isAvailable {
                        Button(action: {
                            showingQuickCamera = true
                        }) {
                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.green)
                                .shadow(radius: 4)
                        }
                        .padding(.trailing, 10)
                    }

                    Button(action: {
                        showingAddMemory = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                            .shadow(radius: 4)
                    }
                    .padding(.trailing, 30)
                }
            }
        }
        .sheet(isPresented: $showingAddMemory) {
            AddMemoryView()
        }
        .sheet(isPresented: $showingQuickCamera) {
            QuickCameraView()
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
}

#Preview {
    ContentView()
}
