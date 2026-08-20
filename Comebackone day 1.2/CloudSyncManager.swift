//
//  CloudSyncManager.swift
//  Comebackone day 1.2
//
//  Syncs memories to the user's private CloudKit database via CKSyncEngine.
//  Each memory is one record in a custom zone; photos travel as CKAssets.
//  Offline-first: the engine queues changes and retries automatically, and
//  everything keeps working locally when no iCloud account is available.
//

import CloudKit
import Foundation

final class CloudSyncManager {
    static let containerID = "iCloud.com.michaeljee.Comebackone-day-1-1"
    static let zoneID = CKRecordZone.ID(zoneName: "TravelMemories", ownerName: CKCurrentUserDefaultName)
    static let recordType: CKRecord.RecordType = "TravelMemory"

    private weak var store: MemoryStore?
    private var engine: CKSyncEngine!

    private let stateURL: URL
    private let systemFieldsURL: URL

    /// Last-known CloudKit record metadata per memory, needed to update
    /// existing server records without conflicting with ourselves.
    private var systemFields: [UUID: Data] = [:]

    init(store: MemoryStore) {
        self.store = store
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        stateURL = documents.appendingPathComponent("cloudkit-state.data")
        systemFieldsURL = documents.appendingPathComponent("cloudkit-systemfields.data")
        loadSystemFields()

        var serialization: CKSyncEngine.State.Serialization?
        if let data = try? Data(contentsOf: stateURL) {
            serialization = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }

        let configuration = CKSyncEngine.Configuration(
            database: CKContainer(identifier: Self.containerID).privateCloudDatabase,
            stateSerialization: serialization,
            delegate: self
        )
        engine = CKSyncEngine(configuration)

        // First run with sync: create the zone and upload everything local.
        if serialization == nil {
            resyncAllLocal()
        }
    }

    // MARK: - API for MemoryStore

    func queueSave(_ id: UUID) {
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(Self.recordID(for: id))])
    }

    func queueDelete(_ id: UUID) {
        systemFields[id] = nil
        persistSystemFields()
        engine.state.add(pendingRecordZoneChanges: [.deleteRecord(Self.recordID(for: id))])
    }

    /// Fetch remote changes and push anything pending. Safe to call anytime.
    func syncNow() async {
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
        } catch {
            print("iCloud sync error: \(error.localizedDescription)")
        }
    }

    // MARK: - Event handling (main actor)

    private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) {
        switch event.changeType {
        case .signIn:
            resyncAllLocal()
        case .switchAccounts:
            // Start fresh against the new account and merge local data into it.
            systemFields = [:]
            persistSystemFields()
            resyncAllLocal()
        case .signOut:
            systemFields = [:]
            persistSystemFields()
        @unknown default:
            break
        }
    }

    private func handleFetchedDatabaseChanges(_ event: CKSyncEngine.Event.FetchedDatabaseChanges) {
        for deletion in event.deletions where deletion.zoneID == Self.zoneID {
            // Zone was deleted (e.g. iCloud data cleared). Keep local copies
            // and re-upload them.
            systemFields = [:]
            persistSystemFields()
            resyncAllLocal()
        }
    }

    private func handleFetchedRecordZoneChanges(_ event: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        for modification in event.modifications {
            apply(serverRecord: modification.record)
        }
        for deletion in event.deletions {
            if let uuid = UUID(uuidString: deletion.recordID.recordName) {
                systemFields[uuid] = nil
                store?.applyRemoteDelete(id: uuid)
            }
        }
        persistSystemFields()
    }

    private func handleSentRecordZoneChanges(_ event: CKSyncEngine.Event.SentRecordZoneChanges) {
        for record in event.savedRecords {
            if let uuid = UUID(uuidString: record.recordID.recordName) {
                systemFields[uuid] = encodeSystemFields(record)
            }
        }

        for failure in event.failedRecordSaves {
            let recordID = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                // Another device changed this record first: the server wins.
                if let server = failure.error.serverRecord {
                    apply(serverRecord: server)
                }
            case .zoneNotFound:
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            case .unknownItem:
                // The server never saw this record; resend it as a new one.
                if let uuid = UUID(uuidString: recordID.recordName) {
                    systemFields[uuid] = nil
                }
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            default:
                // Transient errors (network, throttling…) are retried by the engine.
                break
            }
        }
        persistSystemFields()
    }

    // MARK: - Record conversion

    private static func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    private func resyncAllLocal() {
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        let changes = (store?.memories ?? []).map {
            CKSyncEngine.PendingRecordZoneChange.saveRecord(Self.recordID(for: $0.id))
        }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let uuid = UUID(uuidString: recordID.recordName),
              let memory = store?.memory(withID: uuid) else {
            // Deleted locally before it was ever sent.
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }

        let record: CKRecord
        if let data = systemFields[uuid], let decoded = decodeRecord(data) {
            record = decoded
        } else {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        }

        record["name"] = memory.name
        record["latitude"] = memory.latitude
        record["longitude"] = memory.longitude
        record["category"] = memory.category.rawValue
        record["address"] = memory.address
        record["website"] = memory.website
        record["phoneNumber"] = memory.phoneNumber
        record["rating"] = memory.rating
        record["notes"] = memory.notes
        record["dateAdded"] = memory.dateAdded
        record["dateVisited"] = memory.dateVisited
        record["photoFilenames"] = memory.photoFilenames
        record["photos"] = memory.photoFilenames.map { CKAsset(fileURL: PhotoStore.url(for: $0)) }
        record["isReceivedFromShare"] = memory.isReceivedFromShare ? 1 : 0
        record["senderName"] = memory.senderName
        record["tripName"] = memory.tripName
        record["voiceNoteFilename"] = memory.voiceNoteFilename
        record["voiceNote"] = memory.voiceNoteFilename.map { CKAsset(fileURL: VoiceNoteStore.url(for: $0)) }
        record["visitStatus"] = memory.visitStatus.rawValue
        return record
    }

    private func apply(serverRecord record: CKRecord) {
        guard let uuid = UUID(uuidString: record.recordID.recordName),
              let name = record["name"] as? String,
              let latitude = record["latitude"] as? Double,
              let longitude = record["longitude"] as? Double else {
            return
        }

        systemFields[uuid] = encodeSystemFields(record)

        // Copy downloaded photo assets into the local photo store.
        let filenames = record["photoFilenames"] as? [String] ?? []
        let assets = record["photos"] as? [CKAsset] ?? []
        for (filename, asset) in zip(filenames, assets) {
            let destination = PhotoStore.url(for: filename)
            if !FileManager.default.fileExists(atPath: destination.path),
               let source = asset.fileURL {
                try? FileManager.default.copyItem(at: source, to: destination)
            }
        }

        let voiceNoteFilename = record["voiceNoteFilename"] as? String
        if let voiceNoteFilename, let voiceAsset = record["voiceNote"] as? CKAsset {
            let destination = VoiceNoteStore.url(for: voiceNoteFilename)
            if !FileManager.default.fileExists(atPath: destination.path),
               let source = voiceAsset.fileURL {
                try? FileManager.default.copyItem(at: source, to: destination)
            }
        }

        let memory = TravelMemory(
            id: uuid,
            name: name,
            latitude: latitude,
            longitude: longitude,
            category: Category(rawValue: record["category"] as? String ?? "") ?? .location,
            photoFilenames: filenames,
            address: record["address"] as? String,
            website: record["website"] as? String,
            phoneNumber: record["phoneNumber"] as? String,
            rating: record["rating"] as? Int ?? 0,
            notes: record["notes"] as? String ?? "",
            dateAdded: record["dateAdded"] as? Date ?? Date(),
            dateVisited: record["dateVisited"] as? Date,
            isReceivedFromShare: (record["isReceivedFromShare"] as? Int ?? 0) != 0,
            senderName: record["senderName"] as? String,
            tripName: record["tripName"] as? String,
            voiceNoteFilename: voiceNoteFilename,
            visitStatus: VisitStatus(rawValue: record["visitStatus"] as? String ?? "") ?? .beenThere
        )
        store?.applyRemoteSave(memory)
    }

    // MARK: - Persistence of sync metadata

    private func persistState(_ serialization: CKSyncEngine.State.Serialization) {
        if let data = try? JSONEncoder().encode(serialization) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    private func persistSystemFields() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: systemFields.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyed) {
            try? data.write(to: systemFieldsURL, options: .atomic)
        }
    }

    private func loadSystemFields() {
        guard let data = try? Data(contentsOf: systemFieldsURL),
              let stringKeyed = try? JSONDecoder().decode([String: Data].self, from: data) else {
            return
        }
        systemFields = Dictionary(uniqueKeysWithValues: stringKeyed.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
    }

    private func encodeSystemFields(_ record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private func decodeRecord(_ data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        return CKRecord(coder: unarchiver)
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudSyncManager: CKSyncEngineDelegate {
    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await MainActor.run {
            switch event {
            case .stateUpdate(let stateUpdate):
                persistState(stateUpdate.stateSerialization)
            case .accountChange(let accountChange):
                handleAccountChange(accountChange)
            case .fetchedDatabaseChanges(let changes):
                handleFetchedDatabaseChanges(changes)
            case .fetchedRecordZoneChanges(let changes):
                handleFetchedRecordZoneChanges(changes)
            case .sentRecordZoneChanges(let changes):
                handleSentRecordZoneChanges(changes)
            case .sentDatabaseChanges, .willFetchChanges, .willFetchRecordZoneChanges,
                 .didFetchRecordZoneChanges, .didFetchChanges, .willSendChanges, .didSendChanges:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            await MainActor.run { self.record(for: recordID) }
        }
    }
}
