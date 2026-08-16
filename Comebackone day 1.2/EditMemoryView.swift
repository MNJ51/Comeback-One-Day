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
            return PhotoStore.thumbnail(for: filename, maxDimension: 160)
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

    @State private var draggingPhotoID: UUID?
    @State private var dragTranslation: CGSize = .zero

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
                                    if let image = photo.image {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
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
                                            .scaleEffect(draggingPhotoID == photo.id ? 1.08 : 1)
                                            .shadow(radius: draggingPhotoID == photo.id ? 6 : 0)
                                            .zIndex(draggingPhotoID == photo.id ? 1 : 0)
                                            .offset(x: draggingPhotoID == photo.id ? dragTranslation.width : 0)
                                            .simultaneousGesture(reorderGesture(for: photo))
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .scrollDisabled(draggingPhotoID != nil)
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

    /// A touch-and-hold-then-drag gesture that reorders `photos` live as the finger moves,
    /// so it doesn't fight the horizontal ScrollView's own pan gesture for a quick swipe.
    private func reorderGesture(for photo: EditablePhoto) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    handleDragChange(photo: photo, translation: drag?.translation ?? .zero)
                default:
                    break
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    draggingPhotoID = nil
                    dragTranslation = .zero
                }
            }
    }

    private func handleDragChange(photo: EditablePhoto, translation: CGSize) {
        draggingPhotoID = photo.id
        dragTranslation = translation

        guard let currentIndex = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        let stride = photoSize + photoSpacing
        let slotShift = Int((translation.width / stride).rounded())
        guard slotShift != 0 else { return }
        let targetIndex = min(max(currentIndex + slotShift, 0), photos.count - 1)
        guard targetIndex != currentIndex else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            let moved = photos.remove(at: currentIndex)
            photos.insert(moved, at: targetIndex)
        }
        // The item's "home" slot just changed; keep only the leftover fractional drag.
        dragTranslation.width -= CGFloat(targetIndex - currentIndex) * stride
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
