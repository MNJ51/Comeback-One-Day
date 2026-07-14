//
//  EditMemoryView.swift
//  Comebackone day 1.1
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
            return PhotoStore.thumbnail(for: filename, maxDimension: 160)
        }
    }

    @State private var name: String
    @State private var category: Category
    @State private var dateVisited: Date
    @State private var rating: Int
    @State private var notes: String
    @State private var photos: [EditablePhoto]

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?

    init(memory: TravelMemory) {
        self.memory = memory
        _name = State(initialValue: memory.name)
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

                    DatePicker("Date Visited", selection: $dateVisited, displayedComponents: .date)

                    Picker("Category", selection: $category) {
                        ForEach(Category.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    .pickerStyle(.segmented)
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
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(photos) { photo in
                                    if let image = photo.image {
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

    private func saveChanges() {
        var updated = memory
        updated.name = name.trimmingCharacters(in: .whitespaces)
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
