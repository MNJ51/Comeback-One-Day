//
//  JournalSyncManager.swift
//  Comebackone day 1.2
//
//  Syncs journal entries to the user's private CloudKit database via its own
//  CKSyncEngine — a separate zone/record type from CloudSyncManager (which
//  handles TravelMemory), but the same private database and container, so
//  multiple independent sync engines coexist against one CKContainer. This
//  mirrors CloudSyncManager's structure closely, including CKAsset handling
//  for photos, videos, and the entry's optional voice recording.
//

import CloudKit
import Foundation

final class JournalSyncManager {
    static let zoneID = CKRecordZone.ID(zoneName: "JournalEntries", ownerName: CKCurrentUserDefaultName)
    static let recordType: CKRecord.RecordType = "JournalEntry"

    private weak var store: JournalStore?
    private var engine: CKSyncEngine!

    /// Notifies the store that an entry's save has been confirmed by
    /// CloudKit (`true`) — set by JournalStore, invoked from the sent/fetched
    /// record-zone-changes handlers below, mirroring how applyRemoteSave/
    /// applyRemoteDelete already flow store<->sync-manager.
    var onSyncStatusChange: ((UUID, Bool) -> Void)?

    private let stateURL: URL
    private let systemFieldsURL: URL
    private var systemFields: [UUID: Data] = [:]

    init(store: JournalStore) {
        self.store = store
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        stateURL = documents.appendingPathComponent("journal-cloudkit-state.data")
        systemFieldsURL = documents.appendingPathComponent("journal-cloudkit-systemfields.data")
        loadSystemFields()

        var serialization: CKSyncEngine.State.Serialization?
        if let data = try? Data(contentsOf: stateURL) {
            serialization = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }

        let configuration = CKSyncEngine.Configuration(
            database: CKContainer(identifier: CloudSyncManager.containerID).privateCloudDatabase,
            stateSerialization: serialization,
            delegate: self
        )
        engine = CKSyncEngine(configuration)

        if serialization == nil {
            resyncAllLocal()
        }
    }

    // MARK: - API for JournalStore

    func queueSave(_ id: UUID) {
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(Self.recordID(for: id))])
    }

    func queueDelete(_ id: UUID) {
        systemFields[id] = nil
        persistSystemFields()
        engine.state.add(pendingRecordZoneChanges: [.deleteRecord(Self.recordID(for: id))])
    }

    func syncNow() async {
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
        } catch {
            print("Journal iCloud sync error: \(error.localizedDescription)")
        }
    }

    // MARK: - Event handling (main actor)

    private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) {
        switch event.changeType {
        case .signIn:
            resyncAllLocal()
        case .switchAccounts:
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
                onSyncStatusChange?(uuid, true)
            }
        }

        for failure in event.failedRecordSaves {
            let recordID = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                if let server = failure.error.serverRecord {
                    apply(serverRecord: server)
                }
                if let uuid = UUID(uuidString: recordID.recordName) {
                    onSyncStatusChange?(uuid, false)
                }
            case .zoneNotFound:
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            case .unknownItem:
                if let uuid = UUID(uuidString: recordID.recordName) {
                    systemFields[uuid] = nil
                }
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            default:
                // Permanent failure (quota exceeded, not authenticated, etc.) —
                // nothing will retry this save, so stop showing it as pending.
                if let uuid = UUID(uuidString: recordID.recordName) {
                    onSyncStatusChange?(uuid, false)
                }
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
        let changes = (store?.entries ?? []).map {
            CKSyncEngine.PendingRecordZoneChange.saveRecord(Self.recordID(for: $0.id))
        }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let uuid = UUID(uuidString: recordID.recordName),
              let entry = store?.entry(withID: uuid) else {
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }

        let record: CKRecord
        if let data = systemFields[uuid], let decoded = decodeRecord(data) {
            record = decoded
        } else {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        }

        record["date"] = entry.date
        record["title"] = entry.title
        record["text"] = entry.text
        record["photoFilenames"] = entry.photoFilenames
        record["photos"] = entry.photoFilenames.map { CKAsset(fileURL: PhotoStore.url(for: $0)) }
        record["videoFilenames"] = entry.videoFilenames
        record["videos"] = entry.videoFilenames.map { CKAsset(fileURL: VideoStore.url(for: $0)) }
        record["linkedMemoryID"] = entry.linkedMemoryID?.uuidString
        record["journalName"] = entry.journalName
        record["latitude"] = entry.latitude
        record["longitude"] = entry.longitude
        record["locationLabel"] = entry.locationLabel
        record["weatherTemperatureCelsius"] = entry.weatherTemperatureCelsius
        record["weatherSymbolName"] = entry.weatherSymbolName
        record["weatherDescription"] = entry.weatherDescription
        record["dateAdded"] = entry.dateAdded
        record["audioFilename"] = entry.audioFilename
        record["audio"] = entry.audioFilename.map { CKAsset(fileURL: VoiceNoteStore.url(for: $0)) }
        record["mood"] = entry.mood?.rawValue
        record["drawingFilename"] = entry.drawingFilename
        record["drawing"] = entry.drawingFilename.map { CKAsset(fileURL: DrawingStore.url(for: $0)) }
        record["sourceAssetIdentifiers"] = entry.sourceAssetIdentifiers
        return record
    }

    private func apply(serverRecord record: CKRecord) {
        guard let uuid = UUID(uuidString: record.recordID.recordName),
              let date = record["date"] as? Date,
              let text = record["text"] as? String else {
            return
        }

        systemFields[uuid] = encodeSystemFields(record)

        // Copy downloaded photo/video assets into local storage.
        let photoFilenames = record["photoFilenames"] as? [String] ?? []
        let photoAssets = record["photos"] as? [CKAsset] ?? []
        for (filename, asset) in zip(photoFilenames, photoAssets) {
            let destination = PhotoStore.url(for: filename)
            if !FileManager.default.fileExists(atPath: destination.path),
               let source = asset.fileURL {
                try? FileManager.default.copyItem(at: source, to: destination)
            }
        }

        let videoFilenames = record["videoFilenames"] as? [String] ?? []
        let videoAssets = record["videos"] as? [CKAsset] ?? []
        for (filename, asset) in zip(videoFilenames, videoAssets) {
            let destination = VideoStore.url(for: filename)
            if !FileManager.default.fileExists(atPath: destination.path),
               let source = asset.fileURL {
                try? FileManager.default.copyItem(at: source, to: destination)
            }
        }

        let audioFilename = record["audioFilename"] as? String
        if let audioFilename, let audioAsset = record["audio"] as? CKAsset {
            let destination = VoiceNoteStore.url(for: audioFilename)
            if !FileManager.default.fileExists(atPath: destination.path),
               let source = audioAsset.fileURL {
                try? FileManager.default.copyItem(at: source, to: destination)
            }
        }

        let drawingFilename = record["drawingFilename"] as? String
        if let drawingFilename, let drawingAsset = record["drawing"] as? CKAsset {
            let destination = DrawingStore.url(for: drawingFilename)
            if !FileManager.default.fileExists(atPath: destination.path),
               let source = drawingAsset.fileURL {
                try? FileManager.default.copyItem(at: source, to: destination)
            }
        }

        let entry = JournalEntry(
            id: uuid,
            date: date,
            title: record["title"] as? String,
            text: text,
            photoFilenames: photoFilenames,
            videoFilenames: videoFilenames,
            linkedMemoryID: (record["linkedMemoryID"] as? String).flatMap(UUID.init),
            journalName: record["journalName"] as? String,
            latitude: record["latitude"] as? Double,
            longitude: record["longitude"] as? Double,
            locationLabel: record["locationLabel"] as? String,
            weatherTemperatureCelsius: record["weatherTemperatureCelsius"] as? Double,
            weatherSymbolName: record["weatherSymbolName"] as? String,
            weatherDescription: record["weatherDescription"] as? String,
            dateAdded: record["dateAdded"] as? Date ?? Date(),
            audioFilename: audioFilename,
            mood: (record["mood"] as? String).flatMap(JournalMood.init(rawValue:)),
            drawingFilename: drawingFilename,
            sourceAssetIdentifiers: record["sourceAssetIdentifiers"] as? [String]
        )
        store?.applyRemoteSave(entry)
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

extension JournalSyncManager: CKSyncEngineDelegate {
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
