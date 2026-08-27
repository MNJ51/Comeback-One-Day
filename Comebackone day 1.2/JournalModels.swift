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

    init(
        id: UUID = UUID(),
        date: Date = Date(),
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
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.date = date
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
