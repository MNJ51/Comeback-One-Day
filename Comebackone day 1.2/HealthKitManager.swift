//
//  HealthKitManager.swift
//  Comebackone day 1.2
//
//  Writes a real HKStateOfMind sample to Apple Health whenever a journal
//  entry's mood is tagged or changed. Same permission-then-toggle shape as
//  JournalReminderManager/LocationManager's proximity nudges: enable()
//  requests authorization and only flips the published flag on success,
//  disable() just flips it off — HealthKit write authorization itself can't
//  be revoked programmatically, so the flag is only ever this app's own
//  gate on whether to attempt future writes.
//

import Combine
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {
    @Published var isHealthKitEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isHealthKitEnabled, forKey: Self.enabledKey)
        }
    }

    private static let enabledKey = "HealthKitMoodSyncEnabled"
    private let store = HKHealthStore()

    init() {
        isHealthKitEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Requests write authorization for State of Mind, then turns the
    /// preference on only if the request didn't error. HealthKit's
    /// authorization API never reveals share/deny status for privacy
    /// reasons, so a successful request doesn't guarantee the user actually
    /// granted access — same sticky-permission spirit as the other toggles
    /// in this app that gate on notification/location authorization.
    func enable() {
        guard isHealthDataAvailable else { return }
        Task {
            do {
                try await store.requestAuthorization(toShare: [HKObjectType.stateOfMindType()], read: [])
                isHealthKitEnabled = true
            } catch {
                // Leave disabled.
            }
        }
    }

    func disable() {
        isHealthKitEnabled = false
    }

    /// Pure mapping, unit-testable without touching HealthKit — JournalMood's
    /// 5 cases onto HKStateOfMind's continuous valence (-1...1).
    nonisolated static func valence(for mood: JournalMood) -> Double {
        switch mood {
        case .amazing: return 1.0
        case .good: return 0.5
        case .okay: return 0.0
        case .down: return -0.5
        case .rough: return -1.0
        }
    }

    /// Fire-and-forget best-effort write; failures are swallowed, matching
    /// how other background work in this app (weather/location capture)
    /// never blocks or surfaces errors to the save flow.
    func save(mood: JournalMood, date: Date) async {
        guard isHealthKitEnabled, isHealthDataAvailable else { return }
        let sample = HKStateOfMind(
            date: date,
            kind: .momentaryEmotion,
            valence: Self.valence(for: mood),
            labels: [],
            associations: []
        )
        try? await store.save(sample)
    }
}
