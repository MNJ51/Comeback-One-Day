//
//  AddMemoryView.swift
//  Comebackone day 1.2
//

import SwiftUI
import MapKit
import PhotosUI
import ImageIO

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
    @State private var tripName = ""
    @State private var voiceNoteFilename: String?

    @State private var searchText = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedPlaceLabel: String?
    @State private var selectedAddress: String?

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickedPhotos: [PickedPhoto] = []
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?

    @State private var geoPhotoItem: PhotosPickerItem?
    @State private var showingNoPhotoLocationAlert = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && selectedCoordinate != nil
    }

    /// Every distinct trip name already in use, for quick-pick chips.
    private var availableTrips: [String] {
        Array(Set(store.memories.compactMap(\.tripName))).sorted()
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

                Section("Trip") {
                    TextField("Trip or city (optional)", text: $tripName)

                    if !availableTrips.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(availableTrips, id: \.self) { trip in
                                    FilterChip(title: trip, color: .accentColor, isSelected: tripName == trip) {
                                        tripName = (tripName == trip) ? "" : trip
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .listRowInsets(EdgeInsets())
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
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

                    PhotosPicker(selection: $geoPhotoItem, matching: .images) {
                        Label("Use a Photo's Location", systemImage: "location.viewfinder")
                    }

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

                    VoiceNoteControl(filename: $voiceNoteFilename, externallyOwnedFilename: nil)
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
                        // Nothing has been saved yet, so any voice note recorded
                        // during this session is an orphan — clean it up.
                        VoiceNoteStore.delete(voiceNoteFilename)
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
            .onChange(of: geoPhotoItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    await useLocation(from: newValue)
                    geoPhotoItem = nil
                }
            }
            .alert("No Location Found", isPresented: $showingNoPhotoLocationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("That photo doesn't have location data attached. This usually happens with screenshots or photos where Location Services was off.")
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

    /// Reads a picked photo's embedded GPS EXIF data and uses it to fill in
    /// the location — for a place the user photographed but forgot to save
    /// at the time. Also adds the photo itself, since it's a record of the
    /// place, and backfills the visit date from when the photo was taken.
    private func useLocation(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let geoData = Self.extractGeoData(from: data) else {
            showingNoPhotoLocationAlert = true
            return
        }
        selectedCoordinate = geoData.coordinate
        selectedPlaceLabel = "Photo location"
        if let dateTaken = geoData.dateTaken {
            dateVisited = dateTaken
        }
        pickedPhotos.append(PickedPhoto(data: data))
        selectedAddress = await LocationSearchService.address(for: geoData.coordinate)
    }

    private struct PhotoGeoData {
        let coordinate: CLLocationCoordinate2D
        let dateTaken: Date?
    }

    private static func extractGeoData(from data: Data) -> PhotoGeoData? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              var latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
              var longitude = gps[kCGImagePropertyGPSLongitude] as? Double else {
            return nil
        }
        if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { latitude = -latitude }
        if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { longitude = -longitude }

        var dateTaken: Date?
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            dateTaken = formatter.date(from: dateString)
        }

        return PhotoGeoData(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            dateTaken: dateTaken
        )
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
            dateVisited: dateVisited,
            tripName: tripName.trimmedNonEmpty,
            voiceNoteFilename: voiceNoteFilename
        )
        store.add(newMemory)
        dismiss()
    }
}
