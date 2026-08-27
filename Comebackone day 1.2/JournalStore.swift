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

    private var isLoading = false
    private var sync: JournalSyncManager?

    private let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("journal.json")

    init() {
        load()
        sync = JournalSyncManager(store: self)
    }

    func add(_ entry: JournalEntry) {
        entries.append(entry)
        sync?.queueSave(entry.id)
    }

    func update(_ entry: JournalEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            sync?.queueSave(entry.id)
        }
    }

    func delete(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
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
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    func applyRemoteDelete(id: UUID) {
        entries.removeAll { $0.id == id }
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
