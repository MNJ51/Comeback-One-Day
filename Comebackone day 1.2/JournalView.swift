//
//  JournalView.swift
//  Comebackone day 1.2
//
//  Day One-style journal: a card feed with hero photos, auto-captured
//  location and weather, entries groupable into named journals, and an
//  optional link to one of the user's saved places.
//

import SwiftUI
import PhotosUI

struct JournalListView: View {
    @EnvironmentObject var journalStore: JournalStore
    @EnvironmentObject var store: MemoryStore
    @EnvironmentObject var locationManager: LocationManager
    @State private var showingAddEntry = false
    @State private var selectedEntry: JournalEntry?
    @State private var filterJournal: String?

    private static let defaultJournalName = "Journal"

    private var sortedEntries: [JournalEntry] {
        journalStore.entries.sorted { $0.date > $1.date }
    }

    /// Every distinct journal name in use, for the filter menu.
    private var availableJournals: [String] {
        Array(Set(journalStore.entries.compactMap(\.journalName))).sorted()
    }

    private var visibleEntries: [JournalEntry] {
        guard let filterJournal else { return sortedEntries }
        return sortedEntries.filter { ($0.journalName ?? Self.defaultJournalName) == filterJournal }
    }

    /// Only worth grouping into sections once more than one journal is
    /// actually in use — otherwise it's just visual clutter.
    private var groupedByJournal: [(journal: String, entries: [JournalEntry])]? {
        guard availableJournals.count > 1 else { return nil }
        let groups = Dictionary(grouping: visibleEntries) { $0.journalName ?? Self.defaultJournalName }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Button {
                    showingAddEntry = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.blue)
                }
                .padding(.top, 4)
                .padding(.bottom, 12)

                Group {
                    if journalStore.entries.isEmpty {
                        ContentUnavailableView(
                            "No Journal Entries Yet",
                            systemImage: "book.closed",
                            description: Text("Tap the + button to write about your day.")
                        )
                    } else {
                        List {
                            if let groupedByJournal {
                                ForEach(groupedByJournal, id: \.journal) { group in
                                    Section(group.journal) {
                                        ForEach(group.entries) { entry in
                                            entryRow(for: entry)
                                        }
                                    }
                                }
                            } else {
                                ForEach(visibleEntries) { entry in
                                    entryRow(for: entry)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .refreshable {
                            await journalStore.syncNow()
                        }
                    }
                }
            }
            .navigationTitle("Journal")
            .toolbar {
                if availableJournals.count > 1 {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker("Journal", selection: $filterJournal) {
                                Text("All Journals").tag(String?.none)
                                ForEach(availableJournals, id: \.self) { journal in
                                    Text(journal).tag(String?.some(journal))
                                }
                            }
                        } label: {
                            Image(systemName: filterJournal == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddEntry) {
                JournalEntryFormSheet(entry: nil)
                    .environmentObject(locationManager)
            }
            .sheet(item: $selectedEntry) { entry in
                JournalEntryFormSheet(entry: entry)
                    .environmentObject(locationManager)
            }
        }
    }

    @ViewBuilder
    private func entryRow(for entry: JournalEntry) -> some View {
        Button {
            selectedEntry = entry
        } label: {
            JournalEntryCard(entry: entry, linkedMemory: linkedMemory(for: entry))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .swipeActions {
            Button("Delete", role: .destructive) {
                journalStore.delete(entry)
            }
        }
    }

    private func linkedMemory(for entry: JournalEntry) -> TravelMemory? {
        guard let id = entry.linkedMemoryID else { return nil }
        return store.memory(withID: id)
    }
}

/// A Day One-style entry card: hero photo (or video poster) with a weather/
/// location caption bar over it when present, then date, text preview, and
/// any linked-place/journal chips.
struct JournalEntryCard: View {
    let entry: JournalEntry
    let linkedMemory: TravelMemory?

    private var heroImage: UIImage? {
        if let coverPhoto = entry.coverPhotoFilename {
            return PhotoStore.thumbnail(for: coverPhoto, maxDimension: 500)
        }
        if let firstVideo = entry.videoFilenames.first {
            return VideoStore.thumbnail(for: firstVideo, maxDimension: 500)
        }
        return nil
    }

    private var mediaCount: Int {
        entry.photoFilenames.count + entry.videoFilenames.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let heroImage {
                ZStack(alignment: .bottomLeading) {
                    Image(uiImage: heroImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipped()

                    if entry.weatherSymbolName != nil || entry.locationLabel != nil {
                        captionBar
                            .padding(10)
                    }

                    if mediaCount > 1 {
                        Text("\(mediaCount)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.5), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .topTrailing)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            VStack(alignment: .leading, spacing: 6) {
                if heroImage == nil, entry.weatherSymbolName != nil || entry.locationLabel != nil {
                    captionBar
                }

                Text(entry.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !entry.text.isEmpty {
                    Text(entry.text)
                        .font(.body)
                        .lineLimit(4)
                }

                if linkedMemory != nil || entry.journalName != nil {
                    HStack(spacing: 6) {
                        if let linkedMemory {
                            HStack(spacing: 4) {
                                Image(systemName: linkedMemory.category.icon)
                                    .font(.caption2)
                                Text(linkedMemory.name)
                                    .font(.caption)
                            }
                            .foregroundStyle(linkedMemory.category.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(linkedMemory.category.color.opacity(0.12), in: Capsule())
                        }

                        if let journalName = entry.journalName {
                            Text(journalName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.secondary.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var captionBar: some View {
        HStack(spacing: 8) {
            if let symbolName = entry.weatherSymbolName {
                HStack(spacing: 3) {
                    Image(systemName: symbolName)
                    if let temperature = entry.weatherTemperatureCelsius {
                        Text("\(Int(temperature.rounded()))°C")
                    }
                }
            }
            if let locationLabel = entry.locationLabel {
                HStack(spacing: 3) {
                    Image(systemName: "mappin")
                    Text(locationLabel)
                }
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(heroImage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(heroImage == nil ? AnyShapeStyle(.clear) : AnyShapeStyle(.black.opacity(0.4)), in: Capsule())
    }
}

/// Compact row used inside a saved place's own detail screen, where a full
/// hero-photo card would be too tall for a nested list.
struct JournalEntryRow: View {
    let entry: JournalEntry
    let linkedMemory: TravelMemory?

    private var thumbnail: UIImage? {
        if let coverPhoto = entry.coverPhotoFilename {
            return PhotoStore.thumbnail(for: coverPhoto, maxDimension: 100)
        }
        if let firstVideo = entry.videoFilenames.first {
            return VideoStore.thumbnail(for: firstVideo, maxDimension: 100)
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !entry.text.isEmpty {
                    Text(entry.text)
                        .font(.body)
                        .lineLimit(3)
                }

                if let linkedMemory {
                    HStack(spacing: 4) {
                        Image(systemName: linkedMemory.category.icon)
                            .font(.caption2)
                        Text(linkedMemory.name)
                            .font(.caption)
                    }
                    .foregroundStyle(linkedMemory.category.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(linkedMemory.category.color.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Add or edit a journal entry: text, its own photos/videos, an auto-
/// captured location + weather snapshot (new entries only), an optional
/// journal name, and an optional link to a saved place.
/// `prefilledMemoryID` pre-links a new entry when opened from that place's
/// own detail screen.
struct JournalEntryFormSheet: View {
    let entry: JournalEntry?
    @EnvironmentObject var journalStore: JournalStore
    @EnvironmentObject var store: MemoryStore
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    /// A photo already on disk (editing) or newly picked bytes (not yet saved).
    private struct EditableEntryPhoto: Identifiable, Equatable {
        let id = UUID()
        var filename: String?
        var data: Data?

        var image: UIImage? {
            if let data { return UIImage(data: data) }
            return PhotoStore.thumbnail(for: filename, maxDimension: 160) ?? PhotoStore.image(for: filename)
        }
    }

    /// A video already on disk (editing) or a newly picked/recorded clip
    /// still at its temporary source URL.
    private struct EditableEntryVideo: Identifiable, Equatable {
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

    @State private var date: Date
    @State private var text: String
    @State private var linkedMemoryID: UUID?
    @State private var journalName: String
    @State private var showingPlacePicker = false
    @State private var isSaving = false

    @State private var photos: [EditableEntryPhoto]
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?

    @State private var videos: [EditableEntryVideo]
    @State private var videoPickerItems: [PhotosPickerItem] = []
    @State private var showingVideoCamera = false
    @State private var capturedVideoURL: URL?

    // Auto-captured on appear for a brand-new entry only — past entries keep
    // whatever they were written with rather than being retroactively tagged.
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var locationLabel: String?
    @State private var weatherTemperatureCelsius: Double?
    @State private var weatherSymbolName: String?
    @State private var weatherDescription: String?
    @State private var isCapturingContext = false

    init(entry: JournalEntry?, prefilledMemoryID: UUID? = nil) {
        self.entry = entry
        _date = State(initialValue: entry?.date ?? Date())
        _text = State(initialValue: entry?.text ?? "")
        _linkedMemoryID = State(initialValue: entry?.linkedMemoryID ?? prefilledMemoryID)
        _journalName = State(initialValue: entry?.journalName ?? "")
        _photos = State(initialValue: entry?.photoFilenames.map { EditableEntryPhoto(filename: $0, data: nil) } ?? [])
        _videos = State(initialValue: entry?.videoFilenames.map { EditableEntryVideo(filename: $0, temporaryURL: nil) } ?? [])
        _latitude = State(initialValue: entry?.latitude)
        _longitude = State(initialValue: entry?.longitude)
        _locationLabel = State(initialValue: entry?.locationLabel)
        _weatherTemperatureCelsius = State(initialValue: entry?.weatherTemperatureCelsius)
        _weatherSymbolName = State(initialValue: entry?.weatherSymbolName)
        _weatherDescription = State(initialValue: entry?.weatherDescription)
    }

    private var linkedMemory: TravelMemory? {
        guard let linkedMemoryID else { return nil }
        return store.memory(withID: linkedMemoryID)
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Every distinct journal name already in use, for quick-pick chips.
    private var availableJournals: [String] {
        Array(Set(journalStore.entries.compactMap(\.journalName))).sorted()
    }

    var body: some View {
        NavigationStack {
            formContent
                .navigationTitle(entry == nil ? "New Entry" : "Edit Entry")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .sheet(isPresented: $showingPlacePicker) {
                    LinkedPlacePicker(selectedMemoryID: $linkedMemoryID)
                }
                .sheet(isPresented: $showingCamera) {
                    CameraView(image: $capturedImage)
                }
                .sheet(isPresented: $showingVideoCamera) {
                    VideoCameraView(videoURL: $capturedVideoURL)
                }
                .onChange(of: capturedImage) { _, newValue in handleCapturedImage(newValue) }
                .onChange(of: pickerItems) { _, newValue in handlePickedPhotoItems(newValue) }
                .onChange(of: capturedVideoURL) { _, newValue in handleCapturedVideo(newValue) }
                .onChange(of: videoPickerItems) { _, newValue in handlePickedVideoItems(newValue) }
                .task {
                    await captureContextIfNeeded()
                }
        }
    }

    private var formContent: some View {
        Form {
            Section {
                detailsSectionContent
            } footer: {
                contextFooter
            }

            Section {
                journalSectionContent
            } header: {
                Text("Journal")
            } footer: {
                Text("Groups entries into a named journal, e.g. \"Personal\" or \"Travel\". Leave blank for the default journal.")
            }

            Section("Photos") {
                photosSectionContent
            }

            Section {
                placeSectionContent
            } footer: {
                Text("Optionally link this entry to one of your saved places.")
            }

            if entry != nil {
                Section {
                    Button("Delete Entry", role: .destructive) {
                        if let entry {
                            journalStore.delete(entry)
                        }
                        dismiss()
                    }
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
                Task { await save() }
            }
            .disabled(!canSave || isSaving)
        }
    }

    private func handleCapturedImage(_ newValue: UIImage?) {
        guard let image = newValue, let data = image.jpegData(compressionQuality: 0.8) else { return }
        photos.append(EditableEntryPhoto(filename: nil, data: data))
        capturedImage = nil
    }

    private func handlePickedPhotoItems(_ newValue: [PhotosPickerItem]) {
        guard !newValue.isEmpty else { return }
        Task {
            for item in newValue {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    photos.append(EditableEntryPhoto(filename: nil, data: data))
                }
            }
            pickerItems = []
        }
    }

    private func handleCapturedVideo(_ newValue: URL?) {
        guard let url = newValue else { return }
        videos.append(EditableEntryVideo(filename: nil, temporaryURL: url))
        capturedVideoURL = nil
    }

    private func handlePickedVideoItems(_ newValue: [PhotosPickerItem]) {
        guard !newValue.isEmpty else { return }
        Task {
            for item in newValue {
                if let video = try? await item.loadTransferable(type: PickedVideo.self) {
                    videos.append(EditableEntryVideo(filename: nil, temporaryURL: video.url))
                }
            }
            videoPickerItems = []
        }
    }

    @ViewBuilder
    private var detailsSectionContent: some View {
        DatePicker("Date", selection: $date, displayedComponents: .date)
        TextField("What happened today?", text: $text, axis: .vertical)
            .lineLimit(5...12)
    }

    @ViewBuilder
    private var contextFooter: some View {
        if isCapturingContext {
            Label("Capturing location and weather…", systemImage: "location.fill")
                .font(.caption)
        } else if locationLabel != nil || weatherSymbolName != nil {
            HStack(spacing: 8) {
                if let weatherSymbolName {
                    Image(systemName: weatherSymbolName)
                }
                Text(contextSummary)
            }
            .font(.caption)
        }
    }

    private var contextSummary: String {
        let weatherPart = weatherDescription.map { description in
            let temperaturePart = weatherTemperatureCelsius.map { ", \(Int($0.rounded()))°C" } ?? ""
            return description + temperaturePart
        }
        return [locationLabel, weatherPart].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var journalSectionContent: some View {
        TextField("Journal name (optional)", text: $journalName)
        if !availableJournals.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableJournals, id: \.self) { name in
                        Button(name) { journalName = name }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
        }
    }

    @ViewBuilder
    private var photosSectionContent: some View {
        if !photos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
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
            Button(action: { showingCamera = true }) {
                Label("Take Photo", systemImage: "camera.fill")
            }
        }

        if !videos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
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
            Button(action: { showingVideoCamera = true }) {
                Label("Take Video", systemImage: "video.fill")
            }
        }
    }

    @ViewBuilder
    private var placeSectionContent: some View {
        Button {
            showingPlacePicker = true
        } label: {
            HStack {
                Label(linkedMemory?.name ?? "Link a Place", systemImage: "mappin.circle")
                Spacer()
                if linkedMemory != nil {
                    Text("Change")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        if linkedMemory != nil {
            Button("Remove Link", role: .destructive) {
                linkedMemoryID = nil
            }
        }
    }

    @ViewBuilder
    private func photoThumbnail(for photo: EditableEntryPhoto) -> some View {
        Group {
            if let image = photo.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            Button(action: { photos.removeAll { $0.id == photo.id } }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private func videoThumbnail(for video: EditableEntryVideo) -> some View {
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
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            Button(action: { videos.removeAll { $0.id == video.id } }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .padding(4)
        }
    }

    /// Only ever runs once, for a brand-new entry, and only if we don't
    /// already have a location (re-opening the sheet shouldn't re-fetch).
    private func captureContextIfNeeded() async {
        guard entry == nil, latitude == nil, let coordinate = locationManager.currentLocation else { return }
        isCapturingContext = true
        latitude = coordinate.latitude
        longitude = coordinate.longitude

        async let label = LocationSearchService.shortLabel(for: coordinate)
        async let weather = AppWeatherService.currentWeather(at: coordinate)
        let (resolvedLabel, resolvedWeather) = await (label, weather)

        locationLabel = resolvedLabel
        weatherTemperatureCelsius = resolvedWeather?.temperatureCelsius
        weatherSymbolName = resolvedWeather?.symbolName
        weatherDescription = resolvedWeather?.description
        isCapturingContext = false
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedJournalName = journalName.trimmedNonEmpty

        var photoFilenames: [String] = []
        for photo in photos {
            if let filename = photo.filename {
                photoFilenames.append(filename)
            } else if let data = photo.data, let filename = PhotoStore.save(data) {
                photoFilenames.append(filename)
            }
        }

        var videoFilenames: [String] = []
        for video in videos {
            if let filename = video.filename {
                videoFilenames.append(filename)
            } else if let temporaryURL = video.temporaryURL, let filename = await VideoStore.save(temporaryURL) {
                videoFilenames.append(filename)
            }
        }

        if let entry {
            var updated = entry
            updated.date = date
            updated.text = trimmedText
            updated.photoFilenames = photoFilenames
            updated.videoFilenames = videoFilenames
            updated.linkedMemoryID = linkedMemoryID
            updated.journalName = trimmedJournalName
            journalStore.update(updated)
        } else {
            journalStore.add(JournalEntry(
                date: date,
                text: trimmedText,
                photoFilenames: photoFilenames,
                videoFilenames: videoFilenames,
                linkedMemoryID: linkedMemoryID,
                journalName: trimmedJournalName,
                latitude: latitude,
                longitude: longitude,
                locationLabel: locationLabel,
                weatherTemperatureCelsius: weatherTemperatureCelsius,
                weatherSymbolName: weatherSymbolName,
                weatherDescription: weatherDescription
            ))
        }
        dismiss()
    }
}

/// Searchable list of saved places to link a journal entry to.
private struct LinkedPlacePicker: View {
    @Binding var selectedMemoryID: UUID?
    @EnvironmentObject var store: MemoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredMemories: [TravelMemory] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.memories }
        return store.memories.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filteredMemories) { memory in
                Button {
                    selectedMemoryID = memory.id
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: memory.category.icon)
                            .foregroundStyle(memory.category.color)
                        Text(memory.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedMemoryID == memory.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search places")
            .navigationTitle("Link a Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
