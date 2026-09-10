//
//  AddEventView.swift
//  Comebackone day 1.2
//
//  Mirrors AddMemoryView's location-search/photo-picking machinery, trimmed
//  to what a future event needs: no "Use Current Location" or "Use a
//  Photo's Location" shortcuts, since an event's location isn't where the
//  user is standing or where a photo was taken — it's searched or dropped
//  on the map like any other address.
//

import SwiftUI
import MapKit
import PhotosUI

struct AddEventView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var eventStore: EventStore
    @EnvironmentObject var locationManager: LocationManager
    @StateObject private var searchService = LocationSearchService()

    @State private var name = ""
    @State private var website = ""
    @State private var date = Date()

    @State private var searchText = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedPlaceLabel: String?
    @State private var selectedAddress: String?
    @State private var previewCameraPosition: MapCameraPosition = .automatic
    @State private var showingAdjustLocation = false

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickedPhotos: [PickedPhoto] = []
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?
    @State private var isSaving = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && selectedCoordinate != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event Details") {
                    TextField("Name", text: $name)

                    TextField("Website (optional)", text: $website)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    DatePicker("Date", selection: $date)
                }

                Section("Location") {
                    locationSectionContent
                }

                Section("Photos") {
                    photosSectionContent
                }
            }
            .navigationTitle("Add Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
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
            .sheet(isPresented: $showingAdjustLocation) {
                AdjustLocationView(initialCoordinate: selectedCoordinate, onConfirm: applyPinnedLocation)
                    .environmentObject(locationManager)
            }
            .onChange(of: capturedImage) { _, newValue in
                if let image = newValue, let data = image.jpegData(compressionQuality: 0.8) {
                    pickedPhotos.append(PickedPhoto(data: data))
                    capturedImage = nil
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                Task { await saveEvent() }
            }
            .disabled(!canSave || isSaving)
        }
    }

    @ViewBuilder
    private var locationSectionContent: some View {
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

        Button {
            showingAdjustLocation = true
        } label: {
            Label("Adjust on Map", systemImage: "mappin.and.ellipse")
        }

        if let coordinate = selectedCoordinate {
            SelectedLocationPreview(
                coordinate: coordinate,
                placeLabel: selectedPlaceLabel,
                address: selectedAddress,
                markerTitle: name.isEmpty ? "New Event" : name,
                cameraPosition: $previewCameraPosition
            )
        }
    }

    @ViewBuilder
    private var photosSectionContent: some View {
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

    private func select(_ result: MKLocalSearchCompletion) {
        Task {
            if let resolved = await searchService.resolve(result) {
                selectedCoordinate = resolved.coordinate
                recenterPreview(on: resolved.coordinate)
                selectedPlaceLabel = resolved.name
                selectedAddress = resolved.address
                if name.trimmingCharacters(in: .whitespaces).isEmpty {
                    name = resolved.name
                }
                if website.trimmingCharacters(in: .whitespaces).isEmpty, let resolvedWebsite = resolved.website {
                    website = resolvedWebsite
                }
                searchText = ""
                searchService.search("")
            }
        }
    }

    /// Same unconditional-overwrite behavior as AddMemoryView's equivalent —
    /// a manually dropped pin is a deliberate correction, so every
    /// location-related field is replaced.
    private func applyPinnedLocation(_ place: PinnedLocation) {
        selectedCoordinate = place.coordinate
        recenterPreview(on: place.coordinate)
        selectedPlaceLabel = place.name
        selectedAddress = place.address
        if let placeName = place.name {
            name = placeName
        }
        website = place.website ?? ""
    }

    private func recenterPreview(on coordinate: CLLocationCoordinate2D) {
        previewCameraPosition = .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }

    private func saveEvent() async {
        guard let coordinate = selectedCoordinate else { return }
        isSaving = true
        defer { isSaving = false }

        let filenames = pickedPhotos.compactMap { PhotoStore.save($0.data) }

        let newEvent = Event(
            name: name.trimmingCharacters(in: .whitespaces),
            date: date,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            address: selectedAddress,
            website: website.trimmedNonEmpty,
            photoFilenames: filenames
        )
        eventStore.add(newEvent)
        dismiss()
    }
}
