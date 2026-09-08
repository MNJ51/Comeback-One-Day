//
//  JournalReminderManager.swift
//  Comebackone day 1.2
//
//  A daily local-notification nudge to write in the journal, matching Apple
//  Journal's own reminder. Modeled on LocationManager.enableProximityNudges's
//  permission-then-toggle shape.
//

import Combine
import UserNotifications

@MainActor
final class JournalReminderManager: ObservableObject {
    @Published var isReminderEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isReminderEnabled, forKey: Self.enabledKey)
            if isReminderEnabled {
                schedule()
            } else {
                cancel()
            }
        }
    }
    @Published var reminderTime: DateComponents {
        didSet {
            UserDefaults.standard.set(reminderTime.hour, forKey: Self.hourKey)
            UserDefaults.standard.set(reminderTime.minute, forKey: Self.minuteKey)
            if isReminderEnabled {
                schedule()
            }
        }
    }

    private static let enabledKey = "JournalReminderEnabled"
    private static let hourKey = "JournalReminderHour"
    private static let minuteKey = "JournalReminderMinute"
    private static let notificationIdentifier = "journal-daily-reminder"

    init() {
        isReminderEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let hour = UserDefaults.standard.object(forKey: Self.hourKey) as? Int ?? 20
        let minute = UserDefaults.standard.object(forKey: Self.minuteKey) as? Int ?? 0
        reminderTime = DateComponents(hour: hour, minute: minute)
    }

    /// Requests notification permission, then turns the reminder on. The
    /// toggle only flips on once permission is actually granted — declining
    /// just leaves it off, same as LocationManager.enableProximityNudges.
    func enable() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                self?.isReminderEnabled = true
            }
        }
    }

    func disable() {
        isReminderEnabled = false
    }

    /// Body is deliberately generic — this schedules a recurring notification
    /// in advance, so it can't embed a streak count that would still be
    /// correct whenever it actually fires.
    private func schedule() {
        let content = UNMutableNotificationContent()
        content.title = "Journal Reminder"
        content.body = "Take a moment to write about today."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: reminderTime, repeats: true)
        let request = UNNotificationRequest(identifier: Self.notificationIdentifier, content: content, trigger: trigger)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        center.add(request)
    }

    private func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
    }
}
