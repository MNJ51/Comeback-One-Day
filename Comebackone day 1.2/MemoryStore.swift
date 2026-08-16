//
//  MemoryStore.swift
//  Comebackone day 1.2
//
//  Owns the memory list and persists it as JSON in the Documents directory.
//  Migrates legacy data that older builds kept (photos included) in UserDefaults.
//

import Foundation
import Combine

class MemoryStore: ObservableObject {
    @Published var memories: [TravelMemory] = [] {
        didSet { save() }
    }

    private var isLoading = false
    private var sync: CloudSyncManager?

    private let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("memories.json")

    private static let legacyDefaultsKey = "SavedMemories"

    init() {
        load()
        sync = CloudSyncManager(store: self)
    }

    func add(_ memory: TravelMemory) {
        memories.append(memory)
        sync?.queueSave(memory.id)
    }

    func update(_ memory: TravelMemory) {
        if let index = memories.firstIndex(where: { $0.id == memory.id }) {
            memories[index] = memory
            sync?.queueSave(memory.id)
        }
    }

    func delete(_ memory: TravelMemory) {
        PhotoStore.delete(memory.photoFilenames)
        memories.removeAll { $0.id == memory.id }
        sync?.queueDelete(memory.id)
    }

    func memory(withID id: UUID) -> TravelMemory? {
        memories.first { $0.id == id }
    }

    /// Fetches remote changes and pushes pending local ones.
    func syncNow() async {
        await sync?.syncNow()
    }

    // MARK: - Applying changes that arrived from iCloud
    // These update local state only; they must not queue new sync work.

    func applyRemoteSave(_ memory: TravelMemory) {
        if let index = memories.firstIndex(where: { $0.id == memory.id }) {
            let removedPhotos = memories[index].photoFilenames.filter { !memory.photoFilenames.contains($0) }
            PhotoStore.delete(removedPhotos)
            memories[index] = memory
        } else {
            memories.append(memory)
        }
    }

    func applyRemoteDelete(id: UUID) {
        if let existing = memories.first(where: { $0.id == id }) {
            PhotoStore.delete(existing.photoFilenames)
            memories.removeAll { $0.id == id }
        }
    }

    // MARK: - Persistence

    private func save() {
        guard !isLoading else { return }
        writeToDisk()
    }

    private func writeToDisk() {
        if let encoded = try? JSONEncoder().encode(memories) {
            try? encoded.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([TravelMemory].self, from: data) {
            memories = decoded
        } else if let migrated = migrateLegacyData() {
            memories = migrated
            writeToDisk()
            UserDefaults.standard.removeObject(forKey: Self.legacyDefaultsKey)
        }
    }

    // MARK: - Legacy migration

    /// The shape older builds stored in UserDefaults, with photo bytes inline.
    private struct LegacyTravelMemory: Codable {
        let id: UUID
        let name: String
        let latitude: Double
        let longitude: Double
        let category: String
        var photoData: Data?
        let dateAdded: Date
        var dateVisited: Date?
    }

    private func migrateLegacyData() -> [TravelMemory]? {
        guard let data = UserDefaults.standard.data(forKey: Self.legacyDefaultsKey),
              let legacy = try? JSONDecoder().decode([LegacyTravelMemory].self, from: data) else {
            return nil
        }
        return legacy.map { old in
            var filenames: [String] = []
            if let photoData = old.photoData, let filename = PhotoStore.save(photoData) {
                filenames = [filename]
            }
            return TravelMemory(
                id: old.id,
                name: old.name,
                latitude: old.latitude,
                longitude: old.longitude,
                category: Category(rawValue: old.category) ?? .location,
                photoFilenames: filenames,
                dateAdded: old.dateAdded,
                dateVisited: old.dateVisited
            )
        }
    }

}
