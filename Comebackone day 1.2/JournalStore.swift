//
//  JournalStore.swift
//  Comebackone day 1.2
//
//  Owns the journal entry list and persists it as JSON in the Documents
//  directory — same shape as MemoryStore, just for journal entries.
//

import Foundation
import Combine

final class JournalStore: ObservableObject {
    @Published var entries: [JournalEntry] = [] {
        didSet { save() }
    }

    /// Entries with a local change not yet confirmed saved by CloudKit —
    /// drives the small "syncing" glyph on JournalEntryCard. Cleared once
    /// JournalSyncManager reports the save back via `onSyncStatusChange`.
    @Published private(set) var pendingEntryIDs: Set<UUID> = []

    private var isLoading = false
    private var sync: JournalSyncManager?

    private let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("journal.json")

    init() {
        load()
        let sync = JournalSyncManager(store: self)
        sync.onSyncStatusChange = { [weak self] id, _ in
            // Either outcome means this save attempt is resolved — a retryable
            // failure requeues separately and doesn't call this at all, so the
            // entry stays correctly marked pending until that retry lands.
            self?.pendingEntryIDs.remove(id)
        }
        self.sync = sync
    }

    func add(_ entry: JournalEntry) {
        entries.append(entry)
        pendingEntryIDs.insert(entry.id)
        sync?.queueSave(entry.id)
    }

    func update(_ entry: JournalEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            pendingEntryIDs.insert(entry.id)
            sync?.queueSave(entry.id)
        }
    }

    func delete(_ entry: JournalEntry) {
        PhotoStore.delete(entry.photoFilenames)
        VideoStore.delete(entry.videoFilenames)
        VoiceNoteStore.delete(entry.audioFilename)
        DrawingStore.delete(entry.drawingFilename)
        entries.removeAll { $0.id == entry.id }
        pendingEntryIDs.remove(entry.id)
        sync?.queueDelete(entry.id)
    }

    func entry(withID id: UUID) -> JournalEntry? {
        entries.first { $0.id == id }
    }

    /// Entries linked to a given saved place, most recent first.
    func entries(linkedTo memoryID: UUID) -> [JournalEntry] {
        entries.filter { $0.linkedMemoryID == memoryID }.sorted { $0.date > $1.date }
    }

    /// Fetches remote changes and pushes pending local ones.
    func syncNow() async {
        await sync?.syncNow()
    }

    // MARK: - Applying changes that arrived from iCloud
    // These update local state only; they must not queue new sync work.

    func applyRemoteSave(_ entry: JournalEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            let removedPhotos = entries[index].photoFilenames.filter { !entry.photoFilenames.contains($0) }
            PhotoStore.delete(removedPhotos)
            let removedVideos = entries[index].videoFilenames.filter { !entry.videoFilenames.contains($0) }
            VideoStore.delete(removedVideos)
            if entries[index].audioFilename != entry.audioFilename {
                VoiceNoteStore.delete(entries[index].audioFilename)
            }
            if entries[index].drawingFilename != entry.drawingFilename {
                DrawingStore.delete(entries[index].drawingFilename)
            }
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    func applyRemoteDelete(id: UUID) {
        if let existing = entries.first(where: { $0.id == id }) {
            PhotoStore.delete(existing.photoFilenames)
            VideoStore.delete(existing.videoFilenames)
            VoiceNoteStore.delete(existing.audioFilename)
            DrawingStore.delete(existing.drawingFilename)
            entries.removeAll { $0.id == id }
        }
    }

    // MARK: - Persistence

    private func save() {
        guard !isLoading else { return }
        writeToDisk()
    }

    private func writeToDisk() {
        if let encoded = try? JSONEncoder().encode(entries) {
            try? encoded.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data) {
            entries = decoded
        }
    }
}
