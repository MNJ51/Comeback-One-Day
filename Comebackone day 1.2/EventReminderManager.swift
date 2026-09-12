//
//  EventReminderManager.swift
//  Comebackone day 1.2
//
//  Two independent local-notification nudges for events: one before an
//  upcoming event (user's choice of 1 week or 1 month ahead), and one a
//  year after an event actually attended — a "remember this?" flashback,
//  notification-based rather than a passive in-app banner (unlike
//  TravelMemory's OnThisDayBanner, which is UI-only). Mirrors two existing
//  patterns at once: JournalReminderManager's permission-then-toggle shape,
//  and LocationManager.updateMonitoredRegions(for:)'s "resync every
//  per-item scheduled thing whenever the collection changes" shape — except
//  driven by an Event's date/attended fields via UNCalendarNotificationTrigger,
//  not by CoreLocation region monitoring.
//

import Combine
import Foundation
import UserNotifications

enum EventReminderLeadTime: String, CaseIterable, Identifiable, Codable {
    case oneWeek, oneMonth

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneWeek: return "1 Week Before"
        case .oneMonth: return "1 Month Before"
        }
    }

    var componentsBeforeEvent: DateComponents {
        switch self {
        case .oneWeek: return DateComponents(day: -7)
        case .oneMonth: return DateComponents(month: -1)
        }
    }
}

@MainActor
final class EventReminderManager: ObservableObject {
    @Published var upcomingNudgesEnabled: Bool {
        didSet {
            UserDefaults.standard.set(upcomingNudgesEnabled, forKey: Self.upcomingEnabledKey)
            reschedule()
        }
    }
    @Published var upcomingLeadTime: EventReminderLeadTime {
        didSet {
            UserDefaults.standard.set(upcomingLeadTime.rawValue, forKey: Self.leadTimeKey)
            reschedule()
        }
    }
    @Published var memoryNudgesEnabled: Bool {
        didSet {
            UserDefaults.standard.set(memoryNudgesEnabled, forKey: Self.memoryEnabledKey)
            reschedule()
        }
    }

    private var knownEvents: [Event] = []

    private static let upcomingEnabledKey = "EventUpcomingNudgesEnabled"
    private static let leadTimeKey = "EventUpcomingLeadTime"
    private static let memoryEnabledKey = "EventMemoryNudgesEnabled"
    private static let upcomingPrefix = "event-upcoming-"
    private static let memoryPrefix = "event-memory-"
    /// Stays comfortably under iOS's 64-pending-local-notification cap,
    /// which this app's Journal daily reminder and wishlist proximity
    /// nudges also draw from — same defensive-cap idea as
    /// LocationManager.maxMonitoredRegions.
    private static let maxScheduledNotifications = 60

    init() {
        upcomingNudgesEnabled = UserDefaults.standard.bool(forKey: Self.upcomingEnabledKey)
        let storedLeadTime = UserDefaults.standard.string(forKey: Self.leadTimeKey).flatMap(EventReminderLeadTime.init(rawValue:))
        upcomingLeadTime = storedLeadTime ?? .oneWeek
        memoryNudgesEnabled = UserDefaults.standard.bool(forKey: Self.memoryEnabledKey)
    }

    /// Requests notification permission, then turns the nudge on — only
    /// flips on once permission is actually granted, same shape as
    /// JournalReminderManager.enable()/LocationManager.enableProximityNudges().
    func enableUpcomingNudges() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { self?.upcomingNudgesEnabled = true }
        }
    }

    func disableUpcomingNudges() {
        upcomingNudgesEnabled = false
    }

    func enableMemoryNudges() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { self?.memoryNudgesEnabled = true }
        }
    }

    func disableMemoryNudges() {
        memoryNudgesEnabled = false
    }

    /// Call whenever EventStore.events changes — recomputes and re-registers
    /// every scheduled notification from scratch. Cheap to call often:
    /// already-correct requests are harmlessly re-added, matching
    /// updateMonitoredRegions's own remove-then-readd approach.
    func updateSchedule(for events: [Event]) {
        knownEvents = events
        reschedule()
    }

    private func reschedule() {
        let events = knownEvents
        let upcomingEnabled = upcomingNudgesEnabled
        let memoryEnabled = memoryNudgesEnabled
        let leadTime = upcomingLeadTime

        Task {
            var desired: [(identifier: String, fireDate: Date, title: String, body: String)] = []

            if upcomingEnabled {
                for event in events {
                    guard let fireDate = Self.upcomingFireDate(for: event, leadTime: leadTime) else { continue }
                    desired.append((
                        Self.upcomingPrefix + event.id.uuidString,
                        fireDate,
                        "Upcoming: \(event.name)",
                        "\(event.name) is coming up on \(Self.formattedDate(event.date))."
                    ))
                }
            }

            if memoryEnabled {
                for event in events {
                    guard let fireDate = Self.memoryFireDate(for: event) else { continue }
                    desired.append((
                        Self.memoryPrefix + event.id.uuidString,
                        fireDate,
                        "One Year Ago Today",
                        "You went to \(event.name) a year ago — worth reliving?"
                    ))
                }
            }

            desired.sort { $0.fireDate < $1.fireDate }
            if desired.count > Self.maxScheduledNotifications {
                desired = Array(desired.prefix(Self.maxScheduledNotifications))
            }

            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let ourPendingIdentifiers = Set(pending.map(\.identifier).filter {
                $0.hasPrefix(Self.upcomingPrefix) || $0.hasPrefix(Self.memoryPrefix)
            })
            let desiredIdentifiers = Set(desired.map(\.identifier))

            let toRemove = ourPendingIdentifiers.subtracting(desiredIdentifiers)
            if !toRemove.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: Array(toRemove))
            }

            let toAdd = desired.filter { !ourPendingIdentifiers.contains($0.identifier) }
            for item in toAdd {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default

                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)
                try? await center.add(request)
            }
        }
    }

    private static func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - Pure logic (unit tested — no UNUserNotificationCenter involved)

    /// The upcoming-event nudge only applies to events not yet attended,
    /// and only if the lead-time-adjusted fire date hasn't already passed
    /// (an event days away with a 1-month lead time has nothing left to
    /// schedule).
    nonisolated static func upcomingFireDate(
        for event: Event,
        leadTime: EventReminderLeadTime,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard !event.attended,
              let fireDate = calendar.date(byAdding: leadTime.componentsBeforeEvent, to: event.date) else {
            return nil
        }
        return fireDate > now ? fireDate : nil
    }

    /// The memory nudge only applies to events actually attended, firing
    /// exactly 12 months after the event's own date — nil once that
    /// anniversary has already passed.
    nonisolated static func memoryFireDate(
        for event: Event,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard event.attended,
              let fireDate = calendar.date(byAdding: .month, value: 12, to: event.date) else {
            return nil
        }
        return fireDate > now ? fireDate : nil
    }
}
