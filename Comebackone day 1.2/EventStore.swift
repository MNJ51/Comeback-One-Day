//
//  EventStore.swift
//  Comebackone day 1.2
//
//  Owns the event bucket list and persists it as JSON in the Documents
//  directory — same shape as JournalStore, just for events.
//

import Foundation
import Combine

final class EventStore: ObservableObject {
    @Published var events: [Event] = [] {
        didSet { save() }
    }

    private var isLoading = false
    private var sync: EventSyncManager?

    private let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("events.json")

    init() {
        load()
        sync = EventSyncManager(store: self)
    }

    func add(_ event: Event) {
        events.append(event)
        sync?.queueSave(event.id)
    }

    func update(_ event: Event) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
            sync?.queueSave(event.id)
        }
    }

    func delete(_ event: Event) {
        PhotoStore.delete(event.photoFilenames)
        events.removeAll { $0.id == event.id }
        sync?.queueDelete(event.id)
    }

    func event(withID id: UUID) -> Event? {
        events.first { $0.id == id }
    }

    /// Fetches remote changes and pushes pending local ones.
    func syncNow() async {
        await sync?.syncNow()
    }

    // MARK: - Applying changes that arrived from iCloud
    // These update local state only; they must not queue new sync work.

    func applyRemoteSave(_ event: Event) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            let removedPhotos = events[index].photoFilenames.filter { !event.photoFilenames.contains($0) }
            PhotoStore.delete(removedPhotos)
            events[index] = event
        } else {
            events.append(event)
        }
    }

    func applyRemoteDelete(id: UUID) {
        if let existing = events.first(where: { $0.id == id }) {
            PhotoStore.delete(existing.photoFilenames)
            events.removeAll { $0.id == id }
        }
    }

    // MARK: - Persistence

    private func save() {
        guard !isLoading else { return }
        writeToDisk()
    }

    private func writeToDisk() {
        if let encoded = try? JSONEncoder().encode(events) {
            try? encoded.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Event].self, from: data) {
            events = decoded
        }
    }
}
