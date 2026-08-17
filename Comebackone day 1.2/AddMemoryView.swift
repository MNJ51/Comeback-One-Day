//
//  AddMemoryView.swift
//  Comebackone day 1.2
//

import SwiftUI
import MapKit
import PhotosUI

/// A photo chosen for a memory but not yet written to disk.
struct PickedPhoto: Identifiable, Equatable {
    let id = UUID()
    let data: Data
}

/// Horizontal strip of picked photos with remove buttons.
struct PhotoStrip: View {
    @Binding var photos: [PickedPhoto]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(photos) { photo in
                    if let image = UIImage(data: photo.data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .topTrailing) {
                                Button(action: {
                                    photos.removeAll { $0.id == photo.id }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .padding(4)
                            }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct AddMemoryView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: MemoryStore
    @EnvironmentObject var locationManager: LocationManager
    @StateObject private var searchService = LocationSearchService()

    @State private var name = ""
    @State private var website = ""
    @State private var phoneNumber = ""
    @State private var category = Category.restaurant
    @State private var dateVisited = Date()
    @State private var rating = 0
    @State private var notes = ""

    @State private var searchText = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedPlaceLabel: String?
    @State private var selectedAddress: String?

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickedPhotos: [PickedPhoto] = []
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && selectedCoordinate != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Place Details") {
                    TextField("Name", text: $name)

                    TextField("Website (optional)", text: $website)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("Phone (optional)", text: $phoneNumber)
                        .keyboardType(.phonePad)

                    DatePicker("Date Visited", selection: $dateVisited, displayedComponents: .date)

                    Picker("Category", selection: $category) {
                        ForEach(Category.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Location") {
                    TextField("Search for a place or address", text: $searchText)
                        .autocorrectionDisabled()

                    ForEach(searchService.results.prefix(5), id: \.self) { result in
                        Button(action: {
                            select(result)
                        }) {
                            VStack(alignment: .leading) {
                                Text(result.title)
                                    .foregroundStyle(.primary)
                                Text(result.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button(action: useCurrentLocation) {
                        Label("Use Current Location", systemImage: "location.fill")
                    }
                    .disabled(locationManager.currentLocation == nil)

                    if locationManager.isDenied {
                        Text("Location access is off. Enable it in Settings to use your current location.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let coordinate = selectedCoordinate {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(selectedPlaceLabel ?? "Selected location", systemImage: "mappin.circle.fill")
                                .foregroundStyle(.green)

                            if let selectedAddress {
                                Text(selectedAddress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Map(position: .constant(.region(MKCoordinateRegion(
                                center: coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            )))) {
                                Marker(name.isEmpty ? "New Memory" : name, coordinate: coordinate)
                            }
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .allowsHitTesting(false)
                        }
                    }
                }

                Section("Rating & Notes") {
                    HStack {
                        Text("Rating")
                        Spacer()
                        StarRatingPicker(rating: $rating)
                    }

                    TextField("What made it special?", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Photos") {
                    if !pickedPhotos.isEmpty {
                        PhotoStrip(photos: $pickedPhotos)
                    }

                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                        Label("Add Photos", systemImage: "photo.on.rectangle.angled")
                    }

                    if CameraView.isAvailable {
                        Button(action: {
                            showingCamera = true
                        }) {
                            Label("Take Photo", systemImage: "camera.fill")
                        }
                    }
                }
            }
            .navigationTitle("Add Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveMemory()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if let location = locationManager.currentLocation {
                    searchService.focus(around: location)
                }
            }
            .onChange(of: searchText) { _, newValue in
                searchService.search(newValue)
            }
            .onChange(of: pickerItems) { _, newValue in
                guard !newValue.isEmpty else { return }
                Task {
                    for item in newValue {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            pickedPhotos.append(PickedPhoto(data: data))
                        }
                    }
                    pickerItems = []
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraView(image: $capturedImage)
            }
            .onChange(of: capturedImage) { _, newValue in
                if let image = newValue, let data = image.jpegData(compressionQuality: 0.8) {
                    pickedPhotos.append(PickedPhoto(data: data))
                    capturedImage = nil
                }
            }
        }
    }

    private func select(_ result: MKLocalSearchCompletion) {
        Task {
            if let resolved = await searchService.resolve(result) {
                selectedCoordinate = resolved.coordinate
                selectedPlaceLabel = resolved.name
                selectedAddress = resolved.address
                if name.trimmingCharacters(in: .whitespaces).isEmpty {
                    name = resolved.name
                }
                // Only fill in what the user hasn't already typed themselves.
                if website.trimmingCharacters(in: .whitespaces).isEmpty, let resolvedWebsite = resolved.website {
                    website = resolvedWebsite
                }
                if phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty, let resolvedPhone = resolved.phoneNumber {
                    phoneNumber = resolvedPhone
                }
                searchText = ""
                searchService.search("")
            }
        }
    }

    private func useCurrentLocation() {
        guard let location = locationManager.currentLocation else { return }
        selectedCoordinate = location
        selectedPlaceLabel = "Current location"
        selectedAddress = nil
        Task {
            selectedAddress = await LocationSearchService.address(for: location)
        }
    }

    private func saveMemory() {
        guard let coordinate = selectedCoordinate else { return }

        let filenames = pickedPhotos.compactMap { PhotoStore.save($0.data) }

        let newMemory = TravelMemory(
            name: name.trimmingCharacters(in: .whitespaces),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            category: category,
            photoFilenames: filenames,
            address: selectedAddress,
            website: website.trimmedNonEmpty,
            phoneNumber: phoneNumber.trimmedNonEmpty,
            rating: rating,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            dateVisited: dateVisited
        )
        store.add(newMemory)
        dismiss()
    }
}
