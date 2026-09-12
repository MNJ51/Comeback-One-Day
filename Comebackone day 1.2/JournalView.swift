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
import CoreLocation
import PencilKit
import Photos

/// Renders a journal entry's body as `Text`, applying the app's lightweight
/// Markdown (bold/italic via `**`/`*`, inserted by RichTextEditor's toolbar)
/// safely — via `AttributedString`, not `Text(LocalizedStringKey:)`, since a
/// dynamic `LocalizedStringKey` also performs printf-style `%`-substitution,
/// which could garble a user's own text if it happens to contain a literal
/// "%" sequence. Lines starting with the toolbar's "- " bullet prefix are
/// rewritten to a real bullet character first, since `Text` has no
/// block-level list rendering to interpret that Markdown syntax itself.
func journalBodyText(_ text: String) -> Text {
    let lines = text.components(separatedBy: "\n").map { line in
        line.hasPrefix("- ") ? "\u{2022}" + line.dropFirst(1) : line
    }
    let rendered = lines.joined(separator: "\n")
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    let attributed = (try? AttributedString(markdown: rendered, options: options)) ?? AttributedString(rendered)
    return Text(attributed)
}

/// Gates arbitrary content behind Face ID/passcode when journal locking is
/// enabled — wraps JournalListView at the tab-content call site so the list
/// itself stays unaware of locking entirely. Re-locks whenever the app
/// backgrounds, and attempts authentication automatically as soon as the
/// gate first appears locked.
struct JournalLockGateView<Content: View>: View {
    @EnvironmentObject var lockManager: JournalLockManager
    @Environment(\.scenePhase) private var scenePhase
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if lockManager.isUnlocked {
                content()
            } else {
                lockedView
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                lockManager.lock()
            }
        }
        .task(id: lockManager.isUnlocked) {
            if lockManager.isLockEnabled && !lockManager.isUnlocked {
                await lockManager.authenticate()
            }
        }
    }

    private var lockedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Journal Locked")
                .font(.headline)
            Button("Unlock") {
                Task { await lockManager.authenticate() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct JournalListView: View {
    @EnvironmentObject var journalStore: JournalStore
    @EnvironmentObject var store: MemoryStore
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var journalAppearanceStore: JournalAppearanceStore
    @State private var showingAddEntry = false
    @State private var selectedEntry: JournalEntry?
    @State private var filterJournal: String?
    @State private var bookmarkedOnly = false
    @State private var searchText = ""
    @State private var suggestedMemory: TravelMemory?

    @State private var showingJournalAppearancePicker = false
    @State private var showingNewJournalEntry = false
    @State private var pendingNewJournalName = ""
    @State private var editingJournalName: String?

    @State private var photoAuthStatus: PHAuthorizationStatus = PhotoLibraryMomentFinder.authorizationStatus
    @State private var moments: [PhotoMoment] = []
    @State private var selectedMomentPrefill: PrefilledMomentData?

    @State private var currentReflectionPrompt = JournalReflectionPrompts.random()
    @State private var selectedReflectionPrompt: ReflectionPromptSelection?
    @AppStorage("journalMoodNudgeDismissed") private var moodNudgeDismissed = false

    private static let defaultJournalName = "Journal"

    private var sortedEntries: [JournalEntry] {
        journalStore.entries.sorted { $0.date > $1.date }
    }

    /// Every distinct journal name in use, for the filter menu.
    private var availableJournals: [String] {
        Array(Set(journalStore.entries.compactMap(\.journalName))).sorted()
    }

    private var currentStreak: Int {
        JournalStreak.currentStreak(entryDates: journalStore.entries.map(\.date))
    }

    private var entriesThisYear: Int {
        journalStore.entries.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .year) }.count
    }

    private var locatedEntryCount: Int {
        journalStore.entries.filter { $0.coordinate != nil }.count
    }

    /// Saved places without a journal entry about them yet, most-recent
    /// first — the candidate pool for the "Write About" suggestions row.
    private var suggestionCandidates: [TravelMemory] {
        let linkedIDs = Set(journalStore.entries.compactMap(\.linkedMemoryID))
        return Array(
            store.memories
                .filter { !linkedIDs.contains($0.id) }
                .sorted { $0.dateAdded > $1.dateAdded }
                .prefix(5)
        )
    }

    /// Every distinct journal name in use, paired with its entry count, for
    /// the home-screen "Journals" list — same grouping JournalInsightsView
    /// already derives for its own breakdown.
    private var journalBreakdown: [(name: String, count: Int)] {
        let groups = Dictionary(grouping: journalStore.entries) { $0.journalName ?? Self.defaultJournalName }
        return groups.map { (name: $0.key, count: $0.value.count) }.sorted { $0.count > $1.count }
    }

    private var visibleEntries: [JournalEntry] {
        var result = sortedEntries
        if let filterJournal {
            result = result.filter { ($0.journalName ?? Self.defaultJournalName) == filterJournal }
        }

        if bookmarkedOnly {
            result = result.filter { $0.isBookmarked == true }
        }

        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter {
                $0.text.localizedCaseInsensitiveContains(query)
                    || ($0.journalName?.localizedCaseInsensitiveContains(query) ?? false)
                    || ($0.locationLabel?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }

        return result
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
            List {
                Section {
                    homeCardsContent
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if journalStore.entries.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Journal Entries Yet",
                            systemImage: "book.closed",
                            description: Text("Tap + to write about your day.")
                        )
                    }
                    .listRowSeparator(.hidden)
                } else if let groupedByJournal {
                    ForEach(groupedByJournal, id: \.journal) { group in
                        Section(group.journal) {
                            ForEach(group.entries) { entry in
                                entryRow(for: entry)
                            }
                        }
                    }
                } else {
                    Section {
                        ForEach(visibleEntries) { entry in
                            entryRow(for: entry)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable {
                await journalStore.syncNow()
            }
            .navigationTitle("Journal")
            .searchable(text: $searchText, prompt: "Search entries")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if availableJournals.count > 1 {
                            Picker("Journal", selection: $filterJournal) {
                                Text("All Journals").tag(String?.none)
                                ForEach(availableJournals, id: \.self) { journal in
                                    let appearance = journalAppearanceStore.appearance(for: journal)
                                    Label(journal, systemImage: appearance.iconName).tag(String?.some(journal))
                                }
                            }
                        }
                        Toggle(isOn: $bookmarkedOnly) {
                            Label("Bookmarked Only", systemImage: "bookmark")
                        }
                    } label: {
                        Image(systemName: (filterJournal == nil && !bookmarkedOnly) ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddEntry = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingAddEntry) {
                JournalEntryFormSheet(entry: nil)
                    .environmentObject(locationManager)
            }
            .sheet(item: $suggestedMemory) { memory in
                JournalEntryFormSheet(entry: nil, prefilledMemoryID: memory.id)
                    .environmentObject(locationManager)
            }
            .sheet(item: $selectedEntry) { entry in
                JournalEntryFormSheet(entry: entry)
                    .environmentObject(locationManager)
            }
            .sheet(isPresented: $showingNewJournalEntry) {
                JournalEntryFormSheet(entry: nil, prefilledJournalName: pendingNewJournalName)
                    .environmentObject(locationManager)
            }
            .sheet(item: $selectedMomentPrefill) { moment in
                JournalEntryFormSheet(entry: nil, prefilledMoment: moment)
                    .environmentObject(locationManager)
            }
            .sheet(item: $selectedReflectionPrompt) { selection in
                JournalEntryFormSheet(entry: nil, prefilledPromptText: selection.prompt)
                    .environmentObject(locationManager)
            }
            .sheet(isPresented: $showingJournalAppearancePicker) {
                JournalAppearancePickerSheet { name, appearance in
                    saveJournalAppearance(oldName: nil, newName: name, appearance: appearance)
                    pendingNewJournalName = name
                    showingNewJournalEntry = true
                }
            }
            .sheet(item: Binding(
                get: { editingJournalName.map { IdentifiableString(value: $0) } },
                set: { editingJournalName = $0?.value }
            )) { wrapped in
                JournalAppearancePickerSheet(
                    existingName: wrapped.value,
                    existingAppearance: journalAppearanceStore.appearance(for: wrapped.value)
                ) { name, appearance in
                    saveJournalAppearance(oldName: wrapped.value, newName: name, appearance: appearance)
                }
            }
            .task {
                if photoAuthStatus == .authorized || photoAuthStatus == .limited {
                    await loadMoments()
                }
            }
        }
    }

    private func requestPhotoAccessAndLoadMoments() async {
        photoAuthStatus = await PhotoLibraryMomentFinder.requestAuthorization()
        if photoAuthStatus == .authorized || photoAuthStatus == .limited {
            await loadMoments()
        }
    }

    private func loadMoments() async {
        let alreadyJournaled = Set(journalStore.entries.compactMap(\.sourceAssetIdentifiers).flatMap { $0 })
        moments = await PhotoLibraryMomentFinder.findMoments(excludingAssetIdentifiers: alreadyJournaled)
    }

    private func selectMoment(_ moment: PhotoMoment) async {
        let photoData = await PhotoLibraryMomentFinder.loadImageData(for: moment.assetIdentifiers)
        selectedMomentPrefill = PrefilledMomentData(
            date: moment.date,
            coordinate: moment.coordinate,
            locationLabel: moment.locationLabel,
            photoData: photoData,
            sourceAssetIdentifiers: moment.assetIdentifiers
        )
    }

    @ViewBuilder
    private var homeCardsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                insightsCard
                placesCard
            }

            if currentStreak > 0 {
                Text("🔥 \(currentStreak)-day streak")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            journalsSection

            reflectionCard

            if let entryMissingMood, !moodNudgeDismissed {
                moodNudgeCard(for: entryMissingMood)
            }

            if !suggestionCandidates.isEmpty {
                smartSuggestionsRow
            }

            suggestedMomentsRow
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    /// The most recent entry with no mood tagged yet — the mood-nudge
    /// card's target when tapped, and its own visibility condition.
    private var entryMissingMood: JournalEntry? {
        sortedEntries.first { $0.mood == nil }
    }

    /// A writing prompt, Apple Journal-style — shuffled locally (no
    /// navigation) via JournalReflectionPrompts, or tapped to start a new
    /// entry seeded with the current prompt via JournalEntryFormSheet's
    /// `prefilledPromptText`.
    private var reflectionCard: some View {
        Button {
            selectedReflectionPrompt = ReflectionPromptSelection(prompt: currentReflectionPrompt)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(currentReflectionPrompt)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    currentReflectionPrompt = JournalReflectionPrompts.random(excluding: currentReflectionPrompt)
                } label: {
                    Image(systemName: "shuffle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.white.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(
                LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
        .buttonStyle(.plain)
    }

    /// Styled after Apple Journal's "No Health Access" nudge card, but
    /// points toward the app's own lightweight mood picker (JournalMood)
    /// instead — this app deliberately doesn't integrate with HealthKit for
    /// mood, so there's no Settings deep link, just a button into the most
    /// recent entry still missing a tag.
    private func moodNudgeCard(for entry: JournalEntry) -> some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Button {
                    moodNudgeDismissed = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Text("🙂")
                .font(.largeTitle)

            Text("Tag How You Felt")
                .font(.headline)

            Text("Add a mood to your recent entries to see how you were feeling over time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                selectedEntry = entry
            } label: {
                Text("Add Mood")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    private var journalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Journals")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingJournalAppearancePicker = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }

            ForEach(journalBreakdown, id: \.name) { item in
                let appearance = journalAppearanceStore.appearance(for: item.name)
                Button {
                    filterJournal = item.name
                } label: {
                    HStack {
                        Image(systemName: appearance.iconName)
                            .foregroundStyle(appearance.resolvedColor)
                            .frame(width: 20)
                        Text(item.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(item.count)")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        editingJournalName = item.name
                    } label: {
                        Label("Edit Appearance", systemImage: "paintpalette")
                    }
                }
            }
        }
    }

    /// Renames every entry in `oldName` to `newName` (if it actually
    /// changed) and moves the appearance record to match — a plain rename
    /// onto an already-existing different journal name is allowed; entries
    /// simply merge into it, the same as renaming a folder onto another.
    private func saveJournalAppearance(oldName: String?, newName: String, appearance: JournalAppearance) {
        if let oldName, oldName != newName {
            for entry in journalStore.entries where entry.journalName == oldName {
                var updated = entry
                updated.journalName = newName
                journalStore.update(updated)
            }
            journalAppearanceStore.appearances[oldName] = nil
            if filterJournal == oldName { filterJournal = newName }
        }
        journalAppearanceStore.appearances[newName] = appearance
    }

    /// Recent same-day, nearby-location photo clusters from the user's
    /// Photos library, offered as journal-entry starting points — Apple
    /// Journal's "moment" suggestions. Needs a dedicated permission the rest
    /// of the app doesn't otherwise ask for, so this stays opt-in: nothing is
    /// requested until the user taps in.
    @ViewBuilder
    private var suggestedMomentsRow: some View {
        if photoAuthStatus == .notDetermined {
            Button {
                Task { await requestPhotoAccessAndLoadMoments() }
            } label: {
                Label("See Suggested Moments From Your Photos", systemImage: "photo.stack")
                    .font(.subheadline)
            }
        } else if (photoAuthStatus == .authorized || photoAuthStatus == .limited), !moments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Suggested Moments")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(moments) { moment in
                            Button {
                                Task { await selectMoment(moment) }
                            } label: {
                                MomentCard(moment: moment)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var insightsCard: some View {
        NavigationLink {
            JournalInsightsView()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entriesThisYear)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Entries this year")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var placesCard: some View {
        NavigationLink {
            JournalMapView()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "map.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(locatedEntryCount)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Places")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    /// Saved places without a journal entry yet, offered as quick-start
    /// prompts — taps straight into a new entry pre-linked to that place via
    /// JournalEntryFormSheet's existing `prefilledMemoryID` parameter.
    private var smartSuggestionsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Write About")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(suggestionCandidates) { memory in
                        Button {
                            suggestedMemory = memory
                        } label: {
                            suggestionCard(for: memory)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Same photo-or-category-icon fallback `MemoryRow`/`MemoryPin` already
    /// use elsewhere in the app — a suggestion for a place with a real photo
    /// should actually show it, not just a generic category icon.
    @ViewBuilder
    private func suggestionCard(for memory: TravelMemory) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let thumbnail = PhotoStore.thumbnail(for: memory.coverPhotoFilename, maxDimension: 240) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        memory.category.color.opacity(0.15)
                        Image(systemName: memory.category.icon)
                            .font(.title3)
                            .foregroundStyle(memory.category.color)
                    }
                }
            }
            .frame(width: 120, height: 70)
            .clipped()

            Text(memory.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(8)
                .frame(width: 120, alignment: .leading)
        }
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

/// Wraps a chosen reflection prompt so it can drive a `.sheet(item:)` the
/// same way `PrefilledMomentData` does for photo moments.
struct ReflectionPromptSelection: Identifiable {
    let id = UUID()
    let prompt: String
}

/// Wraps a plain `String` so an optional journal name can drive a
/// `.sheet(item:)` — used for the edit-appearance flow, where `nil` means
/// no sheet and a non-nil value is the journal name being edited.
struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}

/// A suggested photo moment with its full-resolution image data already
/// loaded, ready to prefill a new entry — the load happens once, right after
/// the user taps a moment card, since PHAsset -> Data conversion is async
/// and JournalEntryFormSheet's init can't be.
struct PrefilledMomentData: Identifiable {
    let id = UUID()
    let date: Date
    let coordinate: CLLocationCoordinate2D?
    let locationLabel: String?
    let photoData: [Data]
    let sourceAssetIdentifiers: [String]
}

/// One suggested-moment card on the Journal home screen — loads its own
/// thumbnail lazily since PhotoLibraryMomentFinder.thumbnail(for:) is async.
private struct MomentCard: View {
    let moment: PhotoMoment
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 120, height: 70)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(moment.date, style: .date)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                if let locationLabel = moment.locationLabel {
                    Text(locationLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .frame(width: 120, alignment: .leading)
        }
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            guard let firstAssetID = moment.assetIdentifiers.first else { return }
            thumbnail = await PhotoLibraryMomentFinder.thumbnail(for: firstAssetID, maxDimension: 240)
        }
    }
}

/// A Day One-style entry card: hero photo (or video poster) with a weather/
/// location caption bar over it when present, then date, text preview, and
/// any linked-place/journal chips.
struct JournalEntryCard: View {
    let entry: JournalEntry
    let linkedMemory: TravelMemory?
    @EnvironmentObject var journalStore: JournalStore
    @EnvironmentObject var journalAppearanceStore: JournalAppearanceStore

    private var heroImage: UIImage? {
        if let coverPhoto = entry.coverPhotoFilename {
            return PhotoStore.thumbnail(for: coverPhoto, maxDimension: 500)
        }
        if let firstVideo = entry.videoFilenames.first {
            return VideoStore.thumbnail(for: firstVideo, maxDimension: 500)
        }
        if let drawingFilename = entry.drawingFilename {
            return DrawingStore.thumbnail(for: drawingFilename, maxDimension: 500)
        }
        return nil
    }

    private var isSyncPending: Bool {
        journalStore.pendingEntryIDs.contains(entry.id)
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

                HStack(spacing: 4) {
                    Text(entry.date, style: .date)
                    if let mood = entry.mood {
                        Text(mood.emoji)
                    }
                    if entry.isBookmarked == true {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.orange)
                    }
                    if isSyncPending {
                        Image(systemName: "icloud.and.arrow.up")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let title = entry.title?.trimmedNonEmpty {
                    Text(title)
                        .font(.headline)
                }

                if !entry.text.isEmpty {
                    journalBodyText(entry.text)
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
                            let appearance = journalAppearanceStore.appearance(for: journalName)
                            HStack(spacing: 4) {
                                Image(systemName: appearance.iconName)
                                    .font(.caption2)
                                Text(journalName)
                                    .font(.caption)
                            }
                            .foregroundStyle(appearance.resolvedColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(appearance.resolvedColor.opacity(0.12), in: Capsule())
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
        if let drawingFilename = entry.drawingFilename {
            return DrawingStore.thumbnail(for: drawingFilename, maxDimension: 100)
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

                if let title = entry.title?.trimmedNonEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }

                if !entry.text.isEmpty {
                    journalBodyText(entry.text)
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
    @State private var title: String
    @State private var text: String
    @State private var pendingWrap: RichTextWrap?
    @State private var linkedMemoryID: UUID?
    @State private var journalName: String
    @State private var showingPlacePicker = false
    @State private var isSaving = false

    @State private var showingAudioSheet = false
    @State private var showingSuggestionsSheet = false
    @State private var composerPhotoAuthStatus: PHAuthorizationStatus = PhotoLibraryMomentFinder.authorizationStatus
    @State private var composerMoments: [PhotoMoment] = []

    @State private var photos: [EditableEntryPhoto]
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?

    @State private var videos: [EditableEntryVideo]
    @State private var videoPickerItems: [PhotosPickerItem] = []
    @State private var showingVideoCamera = false
    @State private var capturedVideoURL: URL?

    @State private var audioFilename: String?
    @State private var mood: JournalMood?
    @State private var isBookmarked: Bool
    @State private var presentFind = false

    @State private var drawing: PKDrawing
    @State private var drawingFilename: String?
    @State private var showingDrawingCanvas = false

    private let sourceAssetIdentifiers: [String]?

    // Auto-captured on appear for a brand-new entry only — past entries keep
    // whatever they were written with rather than being retroactively tagged.
    // Also skipped for an entry prefilled from a photo moment, since that
    // moment already carries its own (past) date and location.
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var locationLabel: String?
    @State private var weatherTemperatureCelsius: Double?
    @State private var weatherSymbolName: String?
    @State private var weatherDescription: String?
    @State private var isCapturingContext = false
    private let suppressAutoContext: Bool

    init(
        entry: JournalEntry?,
        prefilledMemoryID: UUID? = nil,
        prefilledJournalName: String? = nil,
        prefilledMoment: PrefilledMomentData? = nil,
        prefilledPromptText: String? = nil
    ) {
        self.entry = entry
        _date = State(initialValue: entry?.date ?? prefilledMoment?.date ?? Date())
        _title = State(initialValue: entry?.title ?? "")
        // Seeds the body with the prompt as a line to write beneath, not a
        // separate field on JournalEntry — it's just ordinary entry text
        // once written, avoiding a schema change for a one-time seed value.
        _text = State(initialValue: entry?.text ?? prefilledPromptText.map { "\($0)\n\n" } ?? "")
        _linkedMemoryID = State(initialValue: entry?.linkedMemoryID ?? prefilledMemoryID)
        _journalName = State(initialValue: entry?.journalName ?? prefilledJournalName ?? "")
        let momentPhotos = prefilledMoment?.photoData.map { EditableEntryPhoto(filename: nil, data: $0) } ?? []
        _photos = State(initialValue: entry?.photoFilenames.map { EditableEntryPhoto(filename: $0, data: nil) } ?? momentPhotos)
        _videos = State(initialValue: entry?.videoFilenames.map { EditableEntryVideo(filename: $0, temporaryURL: nil) } ?? [])
        _audioFilename = State(initialValue: entry?.audioFilename)
        _mood = State(initialValue: entry?.mood)
        _isBookmarked = State(initialValue: entry?.isBookmarked ?? false)
        _drawing = State(initialValue: DrawingStore.drawing(for: entry?.drawingFilename) ?? PKDrawing())
        _drawingFilename = State(initialValue: entry?.drawingFilename)
        sourceAssetIdentifiers = entry?.sourceAssetIdentifiers ?? prefilledMoment?.sourceAssetIdentifiers
        _latitude = State(initialValue: entry?.latitude ?? prefilledMoment?.coordinate?.latitude)
        _longitude = State(initialValue: entry?.longitude ?? prefilledMoment?.coordinate?.longitude)
        _locationLabel = State(initialValue: entry?.locationLabel ?? prefilledMoment?.locationLabel)
        _weatherTemperatureCelsius = State(initialValue: entry?.weatherTemperatureCelsius)
        _weatherSymbolName = State(initialValue: entry?.weatherSymbolName)
        _weatherDescription = State(initialValue: entry?.weatherDescription)
        suppressAutoContext = prefilledMoment != nil
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
            composerBody
                .toolbar(.hidden, for: .navigationBar)
                // Without this, a downward drag on a short entry (nothing to
                // scroll yet) is captured entirely by the sheet's own
                // swipe-to-dismiss gesture instead of the ScrollView — a
                // partial dismiss-then-bounce-back that can leave content
                // shifted up under topFloatingControls. Matches Apple
                // Journal's own composer, which also only exits via the
                // back chevron, never a swipe.
                .interactiveDismissDisabled()
                .safeAreaInset(edge: .top) { topFloatingControls }
                .safeAreaInset(edge: .bottom) { bottomFloatingToolbar }
                .sheet(isPresented: $showingPlacePicker) {
                    LinkedPlacePicker(selectedMemoryID: $linkedMemoryID)
                }
                .sheet(isPresented: $showingCamera) {
                    CameraView(image: $capturedImage)
                }
                .sheet(isPresented: $showingVideoCamera) {
                    VideoCameraView(videoURL: $capturedVideoURL)
                }
                .sheet(isPresented: $showingDrawingCanvas) {
                    drawingCanvasSheet
                }
                .sheet(isPresented: $showingAudioSheet) {
                    AudioRecordingSheet(filename: $audioFilename, externallyOwnedFilename: entry?.audioFilename)
                }
                .sheet(isPresented: $showingSuggestionsSheet) {
                    composerSuggestionsSheet
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

    /// Edge-to-edge composer body — title, mood, date, context, rich text,
    /// and an inline attachment strip. Replaces the old Form/Section layout;
    /// top padding clears the floating pill, bottom padding clears the
    /// floating icon row.
    private var composerBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Title", text: $title)
                    .font(.title2.weight(.semibold))

                moodPicker

                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                contextFooter

                RichTextEditor(text: $text, placeholder: "Start writing…", pendingWrap: $pendingWrap, presentFind: $presentFind)

                attachmentsStrip
            }
            .padding()
            .padding(.top, 60)
            .padding(.bottom, 76)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var attachmentsStrip: some View {
        if !photos.isEmpty || !videos.isEmpty || drawingThumbnail != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(photos) { photo in photoThumbnail(for: photo) }
                    ForEach(videos) { video in videoThumbnail(for: video) }
                    if let drawingThumbnail {
                        sketchThumbnail(drawingThumbnail)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func sketchThumbnail(_ image: UIImage) -> some View {
        Button {
            showingDrawingCanvas = true
        } label: {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        }
        .buttonStyle(.plain)
        .frame(width: 80, height: 80)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            Button(action: removeSketch) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .padding(4)
        }
    }

    private func removeSketch() {
        if let drawingFilename, drawingFilename != entry?.drawingFilename {
            DrawingStore.delete(drawingFilename)
        }
        drawing = PKDrawing()
        drawingFilename = nil
    }

    /// Circular back button, a center pill (Aa formatting / sketch / •••
    /// overflow), and a circular checkmark Save — floats over the content
    /// the same way BottomActionBar floats over ContentView's tabs.
    private var topFloatingControls: some View {
        HStack {
            Button(action: cancelAndDismiss) {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.thickMaterial, in: Circle())
            }

            Spacer()

            HStack(spacing: 2) {
                Menu {
                    Button { pendingWrap = .bold } label: { Label("Bold", systemImage: "bold") }
                    Button { pendingWrap = .italic } label: { Label("Italic", systemImage: "italic") }
                    Button { pendingWrap = .bullet } label: { Label("Bullet List", systemImage: "list.bullet") }
                } label: {
                    Text("Aa").font(.headline).frame(width: 44, height: 36)
                }

                Button {
                    showingDrawingCanvas = true
                } label: {
                    Image(systemName: "pencil.circle").font(.title3).frame(width: 44, height: 36)
                }

                moreMenu
            }
            .foregroundStyle(.primary)
            .background(.thickMaterial, in: Capsule())

            Spacer()

            Button {
                Task { await save() }
            } label: {
                Image(systemName: "checkmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        (canSave && !isSaving) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.gray.opacity(0.4)),
                        in: Circle()
                    )
            }
            .disabled(!canSave || isSaving)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// Journal picker (existing journals only — creating a brand-new named
    /// journal now happens via the dedicated color/icon picker sheet on the
    /// Journal home screen, not by free-typing a name here), the linked-place
    /// picker, and Delete when editing — consolidates what used to be three
    /// separate Form sections.
    private var moreMenu: some View {
        Menu {
            journalPickerMenuButton
            Button {
                showingPlacePicker = true
            } label: {
                Label(linkedMemory?.name ?? "Link a Place", systemImage: "mappin.circle")
            }
            if linkedMemory != nil {
                Button("Remove Place Link", role: .destructive) { linkedMemoryID = nil }
            }
            Divider()
            if title.trimmedNonEmpty != nil {
                Button("Remove Title", role: .destructive) { title = "" }
            }
            Button {
                isBookmarked.toggle()
            } label: {
                Label(
                    isBookmarked ? "Remove Bookmark" : "Add Bookmark",
                    systemImage: isBookmarked ? "bookmark.slash" : "bookmark"
                )
            }
            Button {
                presentFind = true
            } label: {
                Label("Find in Entry", systemImage: "magnifyingglass")
            }
            if entry != nil {
                Divider()
                Button("Delete Entry", role: .destructive, action: deleteEntryAndDismiss)
            }
        } label: {
            Image(systemName: "ellipsis").font(.headline).frame(width: 44, height: 36)
        }
    }

    private var journalPickerMenuButton: some View {
        Menu {
            Button {
                journalName = ""
            } label: {
                if journalName.trimmedNonEmpty == nil {
                    Label("Default Journal", systemImage: "checkmark")
                } else {
                    Text("Default Journal")
                }
            }
            ForEach(availableJournals, id: \.self) { name in
                Button {
                    journalName = name
                } label: {
                    if journalName == name {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
        } label: {
            Label(journalName.trimmedNonEmpty ?? "Default Journal", systemImage: "book.closed")
        }
    }

    private func cancelAndDismiss() {
        // Nothing has been saved yet, so a newly recorded/replaced voice
        // note or sketch that isn't the entry's original is an orphan —
        // both are written to disk immediately, unlike photos, which stay
        // as in-memory Data until Save.
        if audioFilename != entry?.audioFilename, let audioFilename {
            VoiceNoteStore.delete(audioFilename)
        }
        if drawingFilename != entry?.drawingFilename, let drawingFilename {
            DrawingStore.delete(drawingFilename)
        }
        dismiss()
    }

    private func deleteEntryAndDismiss() {
        if let entry {
            journalStore.delete(entry)
        }
        dismiss()
    }

    /// Six icons, floating above the keyboard the same way `BottomActionBar`
    /// floats over ContentView's tabs. Sparkles and the branch icon stand in
    /// for Apple Journal's AI-rewrite and Journaling-Suggestions icons —
    /// this app has neither, so they're mapped to real, already-built
    /// features instead (see JournalModels.swift's JournalReflectionPrompts
    /// and the moments-loading below).
    private var bottomFloatingToolbar: some View {
        HStack(spacing: 0) {
            toolbarIconButton(systemName: "sparkles") {
                text += (text.isEmpty ? "" : "\n\n") + JournalReflectionPrompts.random()
            }

            PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                toolbarIcon("photo.on.rectangle.angled")
            }

            if CameraView.isAvailable {
                toolbarIconButton(systemName: "camera.fill") { showingCamera = true }
            }

            Menu {
                PhotosPicker(selection: $videoPickerItems, maxSelectionCount: 5, matching: .videos) {
                    Label("Choose Video", systemImage: "photo.on.rectangle")
                }
                if VideoCameraView.isAvailable {
                    Button { showingVideoCamera = true } label: { Label("Record Video", systemImage: "video.fill") }
                }
            } label: {
                toolbarIcon("video.badge.plus")
            }

            toolbarIconButton(systemName: "waveform") { showingAudioSheet = true }

            toolbarIconButton(systemName: "arrow.triangle.branch") {
                Task { await loadComposerMomentsIfNeeded() }
                showingSuggestionsSheet = true
            }
        }
        .padding(.vertical, 10)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 26))
        .shadow(radius: 4)
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private func toolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
    }

    private func toolbarIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolbarIcon(systemName)
        }
        .buttonStyle(.plain)
    }

    /// In-composer suggestions, reusing the same PhotoLibraryMomentFinder
    /// moments the Journal home screen surfaces (JournalListView.loadMoments)
    /// — but tapping one here only appends its photos to the entry already
    /// in progress, never touching date/location the way the home-screen
    /// flow does when seeding a brand-new entry.
    private var composerSuggestionsSheet: some View {
        NavigationStack {
            Group {
                if composerPhotoAuthStatus == .notDetermined {
                    Button("See Suggested Moments From Your Photos") {
                        Task { await requestComposerPhotoAccess() }
                    }
                    .padding()
                } else if composerMoments.isEmpty {
                    ContentUnavailableView(
                        "No Suggestions",
                        systemImage: "photo.stack",
                        description: Text("No recent photo moments to suggest.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                            ForEach(composerMoments) { moment in
                                Button {
                                    Task { await appendMoment(moment) }
                                } label: {
                                    MomentCard(moment: moment)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showingSuggestionsSheet = false }
                }
            }
        }
    }

    private func requestComposerPhotoAccess() async {
        composerPhotoAuthStatus = await PhotoLibraryMomentFinder.requestAuthorization()
        if composerPhotoAuthStatus == .authorized || composerPhotoAuthStatus == .limited {
            await loadComposerMomentsIfNeeded()
        }
    }

    private func loadComposerMomentsIfNeeded() async {
        guard composerPhotoAuthStatus == .authorized || composerPhotoAuthStatus == .limited else { return }
        let alreadyJournaled = Set(journalStore.entries.compactMap(\.sourceAssetIdentifiers).flatMap { $0 })
        composerMoments = await PhotoLibraryMomentFinder.findMoments(excludingAssetIdentifiers: alreadyJournaled)
    }

    private func appendMoment(_ moment: PhotoMoment) async {
        let photoData = await PhotoLibraryMomentFinder.loadImageData(for: moment.assetIdentifiers)
        for data in photoData {
            photos.append(EditableEntryPhoto(filename: nil, data: data))
        }
        showingSuggestionsSheet = false
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

    /// Rendered directly from the in-memory `drawing`, not via DrawingStore
    /// (which reflects only what's already been written to disk) — an
    /// in-session edit that hasn't been saved yet still needs to show here.
    private var drawingThumbnail: UIImage? {
        guard !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds
        guard !bounds.isEmpty else { return nil }
        let scale = min(1, 300 / max(bounds.width, bounds.height))
        return drawing.image(from: bounds, scale: scale)
    }

    private var drawingCanvasSheet: some View {
        NavigationStack {
            DrawingCanvasView(drawing: $drawing)
                .navigationTitle("Sketch")
                .navigationBarTitleDisplayMode(.inline)
                // The form's thumbnail preview already reflects live `drawing`
                // state as soon as a stroke is made, but `drawingFilename` (what
                // actually persists) is only updated by Done below — a swipe
                // dismiss would silently discard strokes the preview already
                // implied were kept, so route every exit through Done/Clear.
                .interactiveDismissDisabled()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Clear", role: .destructive) {
                            drawing = PKDrawing()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            let previous = drawingFilename
                            drawingFilename = drawing.strokes.isEmpty ? nil : DrawingStore.save(drawing)
                            if let previous, previous != entry?.drawingFilename {
                                DrawingStore.delete(previous)
                            }
                            showingDrawingCanvas = false
                        }
                    }
                }
        }
    }

    private var moodPicker: some View {
        HStack(spacing: 6) {
            ForEach(JournalMood.allCases) { candidate in
                Button {
                    mood = (mood == candidate) ? nil : candidate
                } label: {
                    Text(candidate.emoji)
                        .font(.title2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(mood == candidate ? Color.blue.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
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
        guard entry == nil, !suppressAutoContext, latitude == nil, let coordinate = locationManager.currentLocation else { return }
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

        let trimmedTitle = title.trimmedNonEmpty

        if let entry {
            if audioFilename != entry.audioFilename, let oldFilename = entry.audioFilename {
                VoiceNoteStore.delete(oldFilename)
            }
            if drawingFilename != entry.drawingFilename, let oldFilename = entry.drawingFilename {
                DrawingStore.delete(oldFilename)
            }
            var updated = entry
            updated.date = date
            updated.title = trimmedTitle
            updated.text = trimmedText
            updated.photoFilenames = photoFilenames
            updated.videoFilenames = videoFilenames
            updated.linkedMemoryID = linkedMemoryID
            updated.journalName = trimmedJournalName
            updated.audioFilename = audioFilename
            updated.mood = mood
            updated.isBookmarked = isBookmarked
            updated.drawingFilename = drawingFilename
            updated.sourceAssetIdentifiers = sourceAssetIdentifiers
            journalStore.update(updated)
        } else {
            journalStore.add(JournalEntry(
                date: date,
                title: trimmedTitle,
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
                weatherDescription: weatherDescription,
                audioFilename: audioFilename,
                mood: mood,
                isBookmarked: isBookmarked,
                drawingFilename: drawingFilename,
                sourceAssetIdentifiers: sourceAssetIdentifiers
            ))
        }
        dismiss()
    }
}

/// Searchable list of saved places to link a journal entry to.
private struct LinkedPlacePicker: View {
    @Binding var selectedMemoryID: UUID?
    @EnvironmentObject var store: MemoryStore
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var filterCategory: Category?

    /// Every category actually in use, so the chip row only ever shows
    /// choices that narrow something down.
    private var availableCategories: [Category] {
        Array(Set(store.memories.map(\.category))).sorted { $0.rawValue < $1.rawValue }
    }

    private var originLocation: CLLocation? {
        locationManager.currentLocation.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// Nearest-first when location is available (the common case: "which of
    /// my places is this near"), alphabetical otherwise.
    private var filteredMemories: [TravelMemory] {
        var result = store.memories

        if let filterCategory {
            result = result.filter { $0.category == filterCategory }
        }

        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }

        if let originLocation {
            return result.sorted {
                originLocation.distance(from: location(for: $0)) < originLocation.distance(from: location(for: $1))
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    private func location(for memory: TravelMemory) -> CLLocation {
        CLLocation(latitude: memory.latitude, longitude: memory.longitude)
    }

    /// "1.2 km away" (or in meters, under 1 km) from the user's current
    /// location — nil when location isn't available, so the row just
    /// falls back to showing the name alone.
    private func distanceLabel(for memory: TravelMemory) -> String? {
        guard let originLocation else { return nil }
        let distanceMeters = originLocation.distance(from: location(for: memory))
        if distanceMeters < 1000 {
            return "\(Int(distanceMeters)) m away"
        }
        return String(format: "%.1f km away", distanceMeters / 1000)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !availableCategories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(title: "All", color: .gray, isSelected: filterCategory == nil) {
                                filterCategory = nil
                            }
                            ForEach(availableCategories) { category in
                                FilterChip(title: category.rawValue, color: category.color, isSelected: filterCategory == category) {
                                    filterCategory = filterCategory == category ? nil : category
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }

                List(filteredMemories) { memory in
                    Button {
                        selectedMemoryID = memory.id
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: memory.category.icon)
                                .foregroundStyle(memory.category.color)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(memory.name)
                                    .foregroundStyle(.primary)
                                if let distance = distanceLabel(for: memory) {
                                    Text(distance)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selectedMemoryID == memory.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                .listStyle(.plain)
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
