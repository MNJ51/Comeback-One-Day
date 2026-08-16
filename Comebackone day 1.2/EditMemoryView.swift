//
//  EditMemoryView.swift
//  Comebackone day 1.2
//

import SwiftUI
import PhotosUI

struct EditMemoryView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: MemoryStore

    let memory: TravelMemory

    /// A photo in the edit session: either one already on disk or newly picked bytes.
    private struct EditablePhoto: Identifiable, Equatable {
        let id = UUID()
        var filename: String?
        var data: Data?

        var image: UIImage? {
            if let data {
                return UIImage(data: data)
            }
            // Fall back to the full-size file if thumbnail generation fails
            // (e.g. the ImageIO decode path chokes on a particular photo).
            return PhotoStore.thumbnail(for: filename, maxDimension: 160) ?? PhotoStore.image(for: filename)
        }
    }

    @State private var name: String
    @State private var website: String
    @State private var category: Category
    @State private var dateVisited: Date
    @State private var rating: Int
    @State private var notes: String
    @State private var photos: [EditablePhoto]

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?

    private let photoSize: CGFloat = 80
    private let photoSpacing: CGFloat = 10

    init(memory: TravelMemory) {
        self.memory = memory
        _name = State(initialValue: memory.name)
        _website = State(initialValue: memory.website ?? "")
        _category = State(initialValue: memory.category)
        _dateVisited = State(initialValue: memory.dateVisited ?? Date())
        _rating = State(initialValue: memory.rating)
        _notes = State(initialValue: memory.notes)
        _photos = State(initialValue: memory.photoFilenames.map { EditablePhoto(filename: $0, data: nil) })
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
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

                    DatePicker("Date Visited", selection: $dateVisited, displayedComponents: .date)

                    Picker("Category", selection: $category) {
                        ForEach(Category.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
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
                    if !photos.isEmpty {
                        Text("Touch and hold a photo, then drag to reorder. The first photo is the cover.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: photoSpacing) {
                                ForEach(photos) { photo in
                                    photoThumbnail(for: photo)
                                        .draggable(photo.id.uuidString) {
                                            photoThumbnail(for: photo)
                                        }
                                        .dropDestination(for: String.self) { items, _ in
                                            movePhoto(draggedID: items.first, before: photo.id)
                                        }
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
            .navigationTitle("Edit Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!canSave)
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
            .onChange(of: capturedImage) { _, newValue in
                if let image = newValue, let data = image.jpegData(compressionQuality: 0.8) {
                    photos.append(EditablePhoto(filename: nil, data: data))
                    capturedImage = nil
                }
            }
        }
    }

    /// One photo cell: the image (or a placeholder if it failed to load), the cover
    /// badge, and the remove button. Reused for both the strip and the drag preview.
    @ViewBuilder
    private func photoThumbnail(for photo: EditablePhoto) -> some View {
        Group {
            if let image = photo.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // Still show a slot for a photo that failed to load
                // (e.g. not finished downloading from iCloud yet)
                // rather than silently dropping it from the list.
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: photoSize, height: photoSize)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .bottomLeading) {
            if photos.first?.id == photo.id {
                Text("Cover")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue, in: Capsule())
                    .foregroundStyle(.white)
                    .padding(4)
            }
        }
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

    /// Drag-reorder: drops the dragged photo immediately before the target.
    private func movePhoto(draggedID: String?, before targetID: UUID) -> Bool {
        guard let draggedID,
              let from = photos.firstIndex(where: { $0.id.uuidString == draggedID }),
              photos.contains(where: { $0.id == targetID }) else { return false }
        withAnimation {
            let photo = photos.remove(at: from)
            let target = photos.firstIndex(where: { $0.id == targetID }) ?? photos.count
            photos.insert(photo, at: target)
        }
        return true
    }

    private func saveChanges() {
        var updated = memory
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.website = website.trimmedNonEmpty
        updated.category = category
        updated.dateVisited = dateVisited
        updated.rating = rating
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove files for photos the user deleted in this session.
        let keptFilenames = Set(photos.compactMap(\.filename))
        let removed = memory.photoFilenames.filter { !keptFilenames.contains($0) }
        PhotoStore.delete(removed)

        // Write newly added photos to disk, preserving display order.
        updated.photoFilenames = photos.compactMap { photo in
            if let filename = photo.filename {
                return filename
            }
            if let data = photo.data {
                return PhotoStore.save(data)
            }
            return nil
        }

        store.update(updated)
        dismiss()
    }
}
