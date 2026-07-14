//
//  MemoryStore.swift
//  Comebackone day 1.1
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

    private let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("memories.json")

    private static let legacyDefaultsKey = "SavedMemories"
    private static let seedFlagKey = "DidSeedSampleMemories"

    init() {
        load()
    }

    func add(_ memory: TravelMemory) {
        memories.append(memory)
    }

    func update(_ memory: TravelMemory) {
        if let index = memories.firstIndex(where: { $0.id == memory.id }) {
            memories[index] = memory
        }
    }

    func delete(_ memory: TravelMemory) {
        PhotoStore.delete(memory.photoFilenames)
        memories.removeAll { $0.id == memory.id }
    }

    func memory(withID id: UUID) -> TravelMemory? {
        memories.first { $0.id == id }
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
        } else if !UserDefaults.standard.bool(forKey: Self.seedFlagKey) {
            memories = Self.sampleMemories
            writeToDisk()
            UserDefaults.standard.set(true, forKey: Self.seedFlagKey)
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

    // MARK: - Sample data (first launch only)

    private static let sampleMemories: [TravelMemory] = [
        TravelMemory(name: "South Bank", latitude: -27.4698, longitude: 153.0251, category: .location, dateVisited: Date()),
        TravelMemory(name: "Story Bridge Hotel", latitude: -27.4633, longitude: 153.0515, category: .restaurant, dateVisited: Date()),
        TravelMemory(name: "Eagle Street Pier", latitude: -27.4689, longitude: 153.0299, category: .location, dateVisited: Date()),
        TravelMemory(name: "Christian Jacques Bakery", latitude: -27.4707, longitude: 153.0387, category: .foodMarket, dateVisited: Date())
    ]
}
