//
//  JournalModels.swift
//  Comebackone day 1.2
//

import CoreLocation
import Foundation

/// A free-form journal entry for a given day, Day One-style: its own photos
/// and videos, an auto-captured location and weather snapshot from when it
/// was written, an optional link to one of the user's saved places, and an
/// optional journal name so entries can be grouped into separate journals
/// (e.g. "Personal", "Travel") the same lightweight way TravelMemory groups
/// places into trips — a free-text tag, not a separate managed entity.
/// Brand new type (no legacy on-disk shape to support), so synthesized
/// Codable is fine — unlike TravelMemory, which hand-writes its Codable
/// conformance for backward compatibility.
struct JournalEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    /// Optional headline shown above the body text. Optional for the same
    /// Codable-safety reason as `audioFilename`/`mood`.
    var title: String?
    var text: String
    var photoFilenames: [String]
    var videoFilenames: [String]
    /// The saved place (TravelMemory.id) this entry is about, if any.
    var linkedMemoryID: UUID?
    /// Groups this entry into a named journal, e.g. "Personal" or "Travel".
    /// Untagged entries show together as a default journal.
    var journalName: String?
    /// Where the entry was written, captured automatically at creation time.
    var latitude: Double?
    var longitude: Double?
    /// A short reverse-geocoded label for that location, e.g. "Noosa, QLD".
    var locationLabel: String?
    var weatherTemperatureCelsius: Double?
    var weatherSymbolName: String?
    var weatherDescription: String?
    let dateAdded: Date
    /// A single attached voice recording, reusing the same VoiceNoteStore
    /// filesystem/CloudKit plumbing already built for TravelMemory's voice
    /// notes. Optional (not an array like photos/videos) deliberately: it's
    /// Codable-safe for entries persisted before this field existed — a
    /// missing key decodes to nil under synthesized Codable — where a
    /// non-optional array default would not be.
    var audioFilename: String?
    /// A simple in-app mood tag — not Apple's system-level HealthKit State of
    /// Mind (third-party apps can't replicate that as a UI, only write
    /// individual samples to it), just a lightweight per-entry feeling tag.
    /// Optional for the same Codable-safety reason as `audioFilename`.
    var mood: JournalMood?
    /// A PencilKit sketch attached to the entry, stored the same
    /// filename-on-disk way as photos/audio (see DrawingStore). Optional for
    /// the same Codable-safety reason as `audioFilename`/`mood`.
    var drawingFilename: String?
    /// PHAsset local identifiers this entry's photos came from, if it was
    /// created from a Photos-library "moment" suggestion — lets a later
    /// PhotoLibraryMomentFinder.findMoments() call exclude photos already
    /// turned into an entry from being suggested again. Optional for the
    /// same Codable-safety reason as `audioFilename`/`mood`/`drawingFilename`
    /// (nil, not `[]`, so a missing key still decodes cleanly).
    var sourceAssetIdentifiers: [String]?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        title: String? = nil,
        text: String,
        photoFilenames: [String] = [],
        videoFilenames: [String] = [],
        linkedMemoryID: UUID? = nil,
        journalName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationLabel: String? = nil,
        weatherTemperatureCelsius: Double? = nil,
        weatherSymbolName: String? = nil,
        weatherDescription: String? = nil,
        dateAdded: Date = Date(),
        audioFilename: String? = nil,
        mood: JournalMood? = nil,
        drawingFilename: String? = nil,
        sourceAssetIdentifiers: [String]? = nil
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.text = text
        self.photoFilenames = photoFilenames
        self.videoFilenames = videoFilenames
        self.linkedMemoryID = linkedMemoryID
        self.journalName = journalName
        self.latitude = latitude
        self.longitude = longitude
        self.locationLabel = locationLabel
        self.weatherTemperatureCelsius = weatherTemperatureCelsius
        self.weatherSymbolName = weatherSymbolName
        self.weatherDescription = weatherDescription
        self.dateAdded = dateAdded
        self.audioFilename = audioFilename
        self.mood = mood
        self.drawingFilename = drawingFilename
        self.sourceAssetIdentifiers = sourceAssetIdentifiers
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The photo shown on the entry's card; falls back to nil (no video
    /// poster fallback here — the view layer decides how to render that).
    var coverPhotoFilename: String? {
        photoFilenames.first
    }
}

/// A simple in-app mood tag for a journal entry. Deliberately its own small
/// enum rather than a repurposing of the app's `Category` type (Models.swift)
/// — `Category` is a place-type taxonomy (restaurant/cafe/hotel/...) for pins
/// and filter chips, with nothing to do with how a journal entry felt.
enum JournalMood: String, Codable, CaseIterable, Identifiable {
    case amazing, good, okay, down, rough

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .amazing: return "🤩"
        case .good: return "🙂"
        case .okay: return "😐"
        case .down: return "😕"
        case .rough: return "😞"
        }
    }

    var label: String {
        switch self {
        case .amazing: return "Amazing"
        case .good: return "Good"
        case .okay: return "Okay"
        case .down: return "Down"
        case .rough: return "Rough"
        }
    }
}

/// Consecutive-day journaling streak, Apple Journal-style — pure logic over
/// entry dates, no persisted state of its own (always derived fresh from
/// whatever entries currently exist).
enum JournalStreak {
    /// Counts consecutive calendar days backward from `referenceDate` with at
    /// least one entry. If `referenceDate`'s own day has no entry yet, starts
    /// counting from the day before instead — so the streak doesn't visually
    /// break the moment a new day starts, only once a full day passes with
    /// nothing written.
    static func currentStreak(entryDates: [Date], asOf referenceDate: Date = Date(), calendar: Calendar = .current) -> Int {
        guard !entryDates.isEmpty else { return 0 }
        let days = Set(entryDates.map { calendar.startOfDay(for: $0) })

        var cursor = calendar.startOfDay(for: referenceDate)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }
        return streak
    }

    /// The longest run of consecutive days ever journaled, not just the
    /// trailing run from today — for Insights' "longest streak" stat, which
    /// should keep showing a past record even after it's been broken.
    static func longestStreak(entryDates: [Date], calendar: Calendar = .current) -> Int {
        guard !entryDates.isEmpty else { return 0 }
        let days = Set(entryDates.map { calendar.startOfDay(for: $0) }).sorted()

        var longest = 0
        var currentRun = 0
        var previousDay: Date?

        for day in days {
            if let previousDay, let expectedNextDay = calendar.date(byAdding: .day, value: 1, to: previousDay), expectedNextDay == day {
                currentRun += 1
            } else {
                currentRun = 1
            }
            longest = max(longest, currentRun)
            previousDay = day
        }
        return longest
    }

    /// Same shape as `currentStreak`, but counting consecutive *weeks*
    /// (calendar-week-of-year, per `calendar`) with at least one entry,
    /// rather than consecutive days.
    static func currentWeeklyStreak(entryDates: [Date], asOf referenceDate: Date = Date(), calendar: Calendar = .current) -> Int {
        guard !entryDates.isEmpty else { return 0 }
        let weeks = Set(entryDates.compactMap { weekStart(for: $0, calendar: calendar) })

        var cursor = weekStart(for: referenceDate, calendar: calendar)
        guard var cursorWeek = cursor else { return 0 }
        if !weeks.contains(cursorWeek) {
            guard let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: cursorWeek) else { return 0 }
            cursorWeek = previousWeek
        }
        cursor = cursorWeek

        var streak = 0
        while let week = cursor, weeks.contains(week) {
            streak += 1
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: week)
        }
        return streak
    }

    /// Same shape as `longestStreak`, but for consecutive weeks.
    static func longestWeeklyStreak(entryDates: [Date], calendar: Calendar = .current) -> Int {
        guard !entryDates.isEmpty else { return 0 }
        let weeks = Set(entryDates.compactMap { weekStart(for: $0, calendar: calendar) }).sorted()

        var longest = 0
        var currentRun = 0
        var previousWeek: Date?

        for week in weeks {
            if let previousWeek, let expectedNextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: previousWeek), expectedNextWeek == week {
                currentRun += 1
            } else {
                currentRun = 1
            }
            longest = max(longest, currentRun)
            previousWeek = week
        }
        return longest
    }

    private static func weekStart(for date: Date, calendar: Calendar) -> Date? {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components)
    }
}
