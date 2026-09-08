//
//  JournalLockManager.swift
//  Comebackone day 1.2
//
//  An optional Face ID/passcode gate on the Journal tab, matching Apple
//  Journal's own privacy lock. Modeled on LocationManager's shape: a
//  UserDefaults-backed toggle plus published status the view layer reacts to.
//

import Combine
import LocalAuthentication

@MainActor
final class JournalLockManager: ObservableObject {
    @Published var isLockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isLockEnabled, forKey: Self.enabledKey)
            if !isLockEnabled {
                isUnlocked = true
            }
        }
    }
    @Published private(set) var isUnlocked: Bool

    private static let enabledKey = "JournalLockEnabled"

    init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        isLockEnabled = enabled
        isUnlocked = !enabled
    }

    /// Called when the app backgrounds — re-locks so returning to the app
    /// requires authenticating again, the same way a secure-notes-style
    /// screen would.
    func lock() {
        guard isLockEnabled else { return }
        isUnlocked = false
    }

    @discardableResult
    func authenticate() async -> Bool {
        let context = LAContext()
        var evaluationError: NSError?
        // No passcode/biometrics enrolled on this device — don't lock the
        // user out of their own journal over a device configuration choice.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            isUnlocked = true
            return true
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your journal")
            isUnlocked = success
            return success
        } catch {
            return false
        }
    }
}
