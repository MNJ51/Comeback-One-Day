//
//  EditMemoryView.swift
//  Comebackone day 1.2
//

import SwiftUI
import PhotosUI
import CoreTransferable

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

    /// A video in the edit session: either one already on disk or a newly
    /// picked/recorded clip still at its temporary source URL.
    private struct EditableVideo: Identifiable, Equatable {
        let id = UUID()
        var filename: String?
        var temporaryURL: URL?

        var thumbnail: UIImage? {
            if let temporaryURL {
                return VideoStore.thumbnail(forTemporaryFileAt: temporaryURL, maxDimension: 160)
            }
            return VideoStore.thumbnail(for: filename, maxDimension: 160)
        }
    }

    @State private var name: String
    @State private var website: String
    @State private var phoneNumber: String
    @State private var category: Category
    @State private var visitStatus: VisitStatus
    @State private var isGlutenFree: Bool
    @State private var dateVisited: Date
    @State private var rating: Int
    @State private var notes: String
    @State private var photos: [EditablePhoto]
    @State private var tripName: String
    @State private var voiceNoteFilename: String?

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?
    @State private var showingReorderSheet = false

    @State private var videos: [EditableVideo]
    @State private var videoPickerItems: [PhotosPickerItem] = []
    @State private var showingVideoCamera = false
    @State private var capturedVideoURL: URL?
    @State private var isSaving = false

    private let photoSize: CGFloat = 80
    private let photoSpacing: CGFloat = 10

    init(memory: TravelMemory) {
        self.memory = memory
        _name = State(initialValue: memory.name)
        _website = State(initialValue: memory.website ?? "")
        _phoneNumber = State(initialValue: memory.phoneNumber ?? "")
        _category = State(initialValue: memory.category)
        _visitStatus = State(initialValue: memory.visitStatus)
        _isGlutenFree = State(initialValue: memory.isGlutenFree)
        _dateVisited = State(initialValue: memory.dateVisited ?? Date())
        _rating = State(initialValue: memory.rating)
        _notes = State(initialValue: memory.notes)
        _photos = State(initialValue: memory.photoFilenames.map { EditablePhoto(filename: $0, data: nil) })
        _videos = State(initialValue: memory.videoFilenames.map { EditableVideo(filename: $0, temporaryURL: nil) })
        _tripName = State(initialValue: memory.tripName ?? "")
        _voiceNoteFilename = State(initialValue: memory.voiceNoteFilename)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
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

                    Picker("Status", selection: $visitStatus) {
                        ForEach(VisitStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)

                    if visitStatus == .beenThere {
                        DatePicker("Date Visited", selection: $dateVisited, displayedComponents: .date)
                    }

                    Picker("Category", selection: $category) {
                        ForEach(Category.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)

                    if category.isFoodRelated {
                        Toggle("Gluten Free Options", isOn: $isGlutenFree)
                    }
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

                Section("Rating & Notes") {
                    HStack {
                        Text("Rating")
                        Spacer()
                        StarRatingPicker(rating: $rating)
                    }

                    TextField("What made it special?", text: $notes, axis: .vertical)
                        .lineLimit(3...6)

                    VoiceNoteControl(filename: $voiceNoteFilename, externallyOwnedFilename: memory.voiceNoteFilename)
                }

                Section("Photos") {
                    if !photos.isEmpty {
                        Text("The first photo is the cover.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: photoSpacing) {
                                ForEach(photos) { photo in
                                    photoThumbnail(for: photo)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        if photos.count > 1 {
                            Button {
                                showingReorderSheet = true
                            } label: {
                                Label("Reorder Photos", systemImage: "arrow.left.arrow.right")
                            }
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

                Section("Videos") {
                    if !videos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: photoSpacing) {
                                ForEach(videos) { video in
                                    videoThumbnail(for: video)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    PhotosPicker(selection: $videoPickerItems, maxSelectionCount: 5, matching: .videos) {
                        Label("Add Video", systemImage: "video.badge.plus")
                    }

                    if VideoCameraView.isAvailable {
                        Button(action: {
                            showingVideoCamera = true
                        }) {
                            Label("Take Video", systemImage: "video.fill")
                        }
                    }
                }
            }
            .navigationTitle("Edit Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Only clean up if this session recorded a *new* voice note —
                        // the originally-saved file (if unchanged, or just deleted in
                        // this session) must survive a cancel untouched.
                        if voiceNoteFilename != memory.voiceNoteFilename, let voiceNoteFilename {
                            VoiceNoteStore.delete(voiceNoteFilename)
                        }
                        dismiss()
                    }
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
            .onChange(of: capturedImage) { _, newValue in
                if let image = newValue, let data = image.jpegData(compressionQuality: 0.8) {
                    photos.append(EditablePhoto(filename: nil, data: data))
                    capturedImage = nil
                }
            }
            .sheet(isPresented: $showingReorderSheet) {
                PhotoReorderSheet(photos: $photos)
            }
            .onChange(of: videoPickerItems) { _, newValue in
                guard !newValue.isEmpty else { return }
                Task {
                    for item in newValue {
                        if let video = try? await item.loadTransferable(type: PickedVideo.self) {
                            videos.append(EditableVideo(filename: nil, temporaryURL: video.url))
                        }
                    }
                    videoPickerItems = []
                }
            }
            .sheet(isPresented: $showingVideoCamera) {
                VideoCameraView(videoURL: $capturedVideoURL)
            }
            .onChange(of: capturedVideoURL) { _, newValue in
                if let url = newValue {
                    videos.append(EditableVideo(filename: nil, temporaryURL: url))
                    capturedVideoURL = nil
                }
            }
        }
    }

    /// One photo cell: the image (or a placeholder if it failed to load), the cover
    /// badge, and the remove button.
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

    /// One video cell: the poster-frame thumbnail (or a placeholder if it
    /// failed to load) and the remove button.
    @ViewBuilder
    private func videoThumbnail(for video: EditableVideo) -> some View {
        ZStack {
            if let thumbnail = video.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(.white, .black.opacity(0.4))
        }
        .frame(width: photoSize, height: photoSize)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            Button(action: {
                videos.removeAll { $0.id == video.id }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .padding(4)
        }
    }

    private func saveChanges() async {
        isSaving = true
        defer { isSaving = false }
        var updated = memory
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.website = website.trimmedNonEmpty
        updated.phoneNumber = phoneNumber.trimmedNonEmpty
        updated.category = category
        updated.visitStatus = visitStatus
        updated.isGlutenFree = category.isFoodRelated && isGlutenFree
        updated.dateVisited = visitStatus == .beenThere ? dateVisited : nil
        updated.rating = rating
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.tripName = tripName.trimmedNonEmpty

        // The old voice note file, if it was replaced or removed this session.
        if voiceNoteFilename != memory.voiceNoteFilename, let oldFilename = memory.voiceNoteFilename {
            VoiceNoteStore.delete(oldFilename)
        }
        updated.voiceNoteFilename = voiceNoteFilename

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

        // Remove files for videos the user deleted in this session.
        let keptVideoFilenames = Set(videos.compactMap(\.filename))
        let removedVideos = memory.videoFilenames.filter { !keptVideoFilenames.contains($0) }
        VideoStore.delete(removedVideos)

        // Compress and write newly added videos to disk, preserving display order.
        var videoFilenames: [String] = []
        for video in videos {
            if let filename = video.filename {
                videoFilenames.append(filename)
            } else if let temporaryURL = video.temporaryURL, let filename = await VideoStore.save(temporaryURL) {
                videoFilenames.append(filename)
            }
        }
        updated.videoFilenames = videoFilenames

        store.update(updated)
        dismiss()
    }

    /// A dedicated screen for reordering, separate from the browsing strip above.
    ///
    /// Three different drag techniques on the horizontal photo strip all lost the
    /// same fight: a drag and a horizontal scroll swipe look identical to the
    /// gesture system at touch-down, and on this hardware that ambiguity broke
    /// scrolling outright rather than resolving cleanly either way. A grid has no
    /// competing scroll axis for a drag to fight — everything fits without
    /// scrolling for a normal photo count — so native drag-and-drop just works.
    private struct PhotoReorderSheet: View {
        @Binding var photos: [EditablePhoto]
        @Environment(\.dismiss) private var dismiss

        private let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]

        var body: some View {
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(photos) { photo in
                            thumbnail(for: photo)
                                .draggable(photo.id.uuidString) {
                                    thumbnail(for: photo)
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    move(draggedID: items.first, before: photo.id)
                                }
                        }
                    }
                    .padding()
                }
                .navigationTitle("Reorder Photos")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }

        @ViewBuilder
        private func thumbnail(for photo: EditablePhoto) -> some View {
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
            .frame(width: 90, height: 90)
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
        }

        private func move(draggedID: String?, before targetID: UUID) -> Bool {
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
    }
}
