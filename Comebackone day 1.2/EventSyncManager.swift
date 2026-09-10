//
//  EventSyncManager.swift
//  Comebackone day 1.2
//
//  Syncs bucket-list events to the user's private CloudKit database via its
//  own CKSyncEngine — a separate zone/record type from CloudSyncManager and
//  JournalSyncManager, but the same private database and container, so
//  multiple independent sync engines coexist against one CKContainer. This
//  mirrors JournalSyncManager's structure closely, including CKAsset
//  handling for photos.
//

import CloudKit
import Foundation

final class EventSyncManager {
    static let zoneID = CKRecordZone.ID(zoneName: "Events", ownerName: CKCurrentUserDefaultName)
    static let recordType: CKRecord.RecordType = "Event"

    private weak var store: EventStore?
    private var engine: CKSyncEngine!

    private let stateURL: URL
    private let systemFieldsURL: URL
    private var systemFields: [UUID: Data] = [:]

    init(store: EventStore) {
        self.store = store
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        stateURL = documents.appendingPathComponent("event-cloudkit-state.data")
        systemFieldsURL = documents.appendingPathComponent("event-cloudkit-systemfields.data")
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

    // MARK: - API for EventStore

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
            print("Event iCloud sync error: \(error.localizedDescription)")
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
            }
        }

        for failure in event.failedRecordSaves {
            let recordID = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                if let server = failure.error.serverRecord {
                    apply(serverRecord: server)
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
        let changes = (store?.events ?? []).map {
            CKSyncEngine.PendingRecordZoneChange.saveRecord(Self.recordID(for: $0.id))
        }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let uuid = UUID(uuidString: recordID.recordName),
              let event = store?.event(withID: uuid) else {
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }

        let record: CKRecord
        if let data = systemFields[uuid], let decoded = decodeRecord(data) {
            record = decoded
        } else {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        }

        record["name"] = event.name
        record["date"] = event.date
        record["latitude"] = event.latitude
        record["longitude"] = event.longitude
        record["address"] = event.address
        record["website"] = event.website
        record["photoFilenames"] = event.photoFilenames
        record["photos"] = event.photoFilenames.map { CKAsset(fileURL: PhotoStore.url(for: $0)) }
        record["attended"] = event.attended
        record["dateAdded"] = event.dateAdded
        return record
    }

    private func apply(serverRecord record: CKRecord) {
        guard let uuid = UUID(uuidString: record.recordID.recordName),
              let name = record["name"] as? String,
              let date = record["date"] as? Date,
              let latitude = record["latitude"] as? Double,
              let longitude = record["longitude"] as? Double else {
            return
        }

        systemFields[uuid] = encodeSystemFields(record)

        // Copy downloaded photo assets into local storage.
        let photoFilenames = record["photoFilenames"] as? [String] ?? []
        let photoAssets = record["photos"] as? [CKAsset] ?? []
        for (filename, asset) in zip(photoFilenames, photoAssets) {
            let destination = PhotoStore.url(for: filename)
            if !FileManager.default.fileExists(atPath: destination.path),
               let source = asset.fileURL {
                try? FileManager.default.copyItem(at: source, to: destination)
            }
        }

        let event = Event(
            id: uuid,
            name: name,
            date: date,
            latitude: latitude,
            longitude: longitude,
            address: record["address"] as? String,
            website: record["website"] as? String,
            photoFilenames: photoFilenames,
            attended: record["attended"] as? Bool ?? false,
            dateAdded: record["dateAdded"] as? Date ?? Date()
        )
        store?.applyRemoteSave(event)
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

extension EventSyncManager: CKSyncEngineDelegate {
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
