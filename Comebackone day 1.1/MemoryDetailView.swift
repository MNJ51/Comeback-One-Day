//
//  MemoryDetailView.swift
//  Comebackone day 1.1
//

import SwiftUI
import MapKit

struct MemoryDetailView: View {
    let memoryID: UUID
    @EnvironmentObject var store: MemoryStore
    @Environment(\.dismiss) var dismiss

    @State private var showingEdit = false
    @State private var showingDeleteConfirmation = false

    private var memory: TravelMemory? {
        store.memory(withID: memoryID)
    }

    var body: some View {
        NavigationStack {
            if let memory {
                ScrollView {
                    VStack(spacing: 20) {
                        if !memory.photoFilenames.isEmpty {
                            TabView {
                                ForEach(memory.photoFilenames, id: \.self) { filename in
                                    if let uiImage = PhotoStore.thumbnail(for: filename, maxDimension: 400) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(maxWidth: .infinity)
                                            .clipped()
                                    }
                                }
                            }
                            .tabViewStyle(.page)
                            .frame(height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                        }

                        VStack(alignment: .leading, spacing: 15) {
                            Text(memory.name)
                                .font(.title)
                                .bold()

                            StarRatingLabel(rating: memory.rating)

                            HStack {
                                Image(systemName: "tag.fill")
                                    .foregroundStyle(memory.category.color)
                                Text(memory.category.rawValue)
                                    .foregroundStyle(.secondary)
                            }

                            if let address = memory.address {
                                HStack(alignment: .top) {
                                    Image(systemName: "mappin.and.ellipse")
                                    Text(address)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let dateVisited = memory.dateVisited {
                                HStack {
                                    Image(systemName: "calendar")
                                    Text("Visited: \(dateVisited, style: .date)")
                                        .foregroundStyle(.secondary)
                                }
                            }

                            HStack {
                                Image(systemName: "clock")
                                Text("Added: \(memory.dateAdded, style: .date)")
                                    .foregroundStyle(.secondary)
                            }

                            if !memory.notes.isEmpty {
                                Text(memory.notes)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                        VStack(spacing: 12) {
                            Text("Get Directions")
                                .font(.headline)
                                .padding(.top)

                            HStack(spacing: 15) {
                                DirectionButton(icon: "car.fill", label: "Drive", color: .blue) {
                                    openMaps(memory: memory, mode: MKLaunchOptionsDirectionsModeDriving)
                                }

                                DirectionButton(icon: "figure.walk", label: "Walk", color: .green) {
                                    openMaps(memory: memory, mode: MKLaunchOptionsDirectionsModeWalking)
                                }

                                DirectionButton(icon: "bicycle", label: "Bike", color: .orange) {
                                    openCyclingDirections(memory: memory)
                                }

                                DirectionButton(icon: "bus.fill", label: "Transit", color: .purple) {
                                    openMaps(memory: memory, mode: MKLaunchOptionsDirectionsModeTransit)
                                }
                            }
                        }
                        .padding()

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Place", systemImage: "trash")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    .padding()
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: shareText(for: memory)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(action: {
                                showingEdit = true
                            }) {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive, action: {
                                showingDeleteConfirmation = true
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .sheet(isPresented: $showingEdit) {
                    EditMemoryView(memory: memory)
                }
                .task(id: memoryID) {
                    await fetchAddressIfNeeded()
                }
                .confirmationDialog(
                    "Delete \(memory.name)?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        store.delete(memory)
                        dismiss()
                    }
                } message: {
                    Text("This memory and its photo will be removed.")
                }
            }
        }
    }

    private func shareText(for memory: TravelMemory) -> String {
        var lines = [memory.name]
        if memory.rating > 0 {
            lines.append(String(repeating: "★", count: memory.rating))
        }
        if let address = memory.address {
            lines.append(address)
        }
        if !memory.notes.isEmpty {
            lines.append(memory.notes)
        }
        lines.append("https://maps.apple.com/?ll=\(memory.latitude),\(memory.longitude)&q=\(memory.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? memory.name)")
        return lines.joined(separator: "\n")
    }

    // Memories created before address support (or via Quick Camera) look up
    // their address the first time they're viewed, then keep it.
    private func fetchAddressIfNeeded() async {
        guard var memory = store.memory(withID: memoryID), memory.address == nil else { return }
        guard let address = await LocationSearchService.address(for: memory.coordinate) else { return }
        memory.address = address
        store.update(memory)
    }

    private func openMaps(memory: TravelMemory, mode: String) {
        let location = CLLocation(latitude: memory.latitude, longitude: memory.longitude)
        let mapItem = MKMapItem(location: location, address: nil)
        mapItem.name = memory.name

        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
    }

    // Apple Maps has no cycling launch option, so use the maps.apple.com
    // URL scheme where dirflg=c requests cycling directions.
    private func openCyclingDirections(memory: TravelMemory) {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "daddr", value: "\(memory.latitude),\(memory.longitude)"),
            URLQueryItem(name: "dirflg", value: "c")
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }
}

struct DirectionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption)
            }
            .frame(width: 70, height: 70)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
