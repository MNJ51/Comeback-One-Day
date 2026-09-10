//
//  EditEventView.swift
//  Comebackone day 1.2
//

import SwiftUI
import MapKit
import PhotosUI

struct EditEventView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var eventStore: EventStore
    @EnvironmentObject var locationManager: LocationManager

    let event: Event

    private struct EditablePhoto: Identifiable, Equatable {
        let id = UUID()
        var filename: String?
        var data: Data?

        var image: UIImage? {
            if let data {
                return UIImage(data: data)
            }
            return PhotoStore.thumbnail(for: filename, maxDimension: 160) ?? PhotoStore.image(for: filename)
        }
    }

    @State private var name: String
    @State private var website: String
    @State private var date: Date
    @State private var attended: Bool
    @State private var photos: [EditablePhoto]

    @State private var selectedCoordinate: CLLocationCoordinate2D
    @State private var selectedPlaceLabel: String?
    @State private var selectedAddress: String?
    @State private var previewCameraPosition: MapCameraPosition = .automatic
    @State private var showingAdjustLocation = false

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?
    @State private var isSaving = false

    private let photoSize: CGFloat = 80
    private let photoSpacing: CGFloat = 10

    init(event: Event) {
        self.event = event
        _name = State(initialValue: event.name)
        _website = State(initialValue: event.website ?? "")
        _date = State(initialValue: event.date)
        _attended = State(initialValue: event.attended)
        _photos = State(initialValue: event.photoFilenames.map { EditablePhoto(filename: $0, data: nil) })
        _selectedCoordinate = State(initialValue: event.coordinate)
        _selectedPlaceLabel = State(initialValue: event.name)
        _selectedAddress = State(initialValue: event.address)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
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

                    Toggle("Attended", isOn: $attended)
                }

                Section("Location") {
                    SelectedLocationPreview(
                        coordinate: selectedCoordinate,
                        placeLabel: selectedPlaceLabel,
                        address: selectedAddress,
                        markerTitle: name.isEmpty ? "Event" : name,
                        cameraPosition: $previewCameraPosition
                    )

                    Button {
                        showingAdjustLocation = true
                    } label: {
                        Label("Adjust on Map", systemImage: "mappin.and.ellipse")
                    }
                }

                Section("Photos") {
                    if !photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: photoSpacing) {
                                ForEach(photos) { photo in
                                    photoThumbnail(for: photo)
                                }
                            }
                            .padding(.vertical, 4)
                        }
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
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveChanges() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .onChange(of: pickerItems) { _, newValue in
                guard !newValue.isEmpty else { return }
                Task {
                    for item in newValue {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            photos.append(EditablePhoto(filename: nil, data: data))
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
                    photos.append(EditablePhoto(filename: nil, data: data))
                    capturedImage = nil
                }
            }
        }
    }

    @ViewBuilder
    private func photoThumbnail(for photo: EditablePhoto) -> some View {
        Group {
            if let image = photo.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: photoSize, height: photoSize)
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

    private func saveChanges() async {
        isSaving = true
        defer { isSaving = false }
        var updated = event
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.website = website.trimmedNonEmpty
        updated.date = date
        updated.attended = attended
        updated.latitude = selectedCoordinate.latitude
        updated.longitude = selectedCoordinate.longitude
        updated.address = selectedAddress

        let keptFilenames = Set(photos.compactMap(\.filename))
        let removed = event.photoFilenames.filter { !keptFilenames.contains($0) }
        PhotoStore.delete(removed)

        updated.photoFilenames = photos.compactMap { photo in
            if let filename = photo.filename {
                return filename
            }
            if let data = photo.data {
                return PhotoStore.save(data)
            }
            return nil
        }

        eventStore.update(updated)
        dismiss()
    }
}
