//
//  EventModels.swift
//  Comebackone day 1.2
//

import CoreLocation
import Foundation

/// A concert, festival, or other event the user wants to attend — distinct
/// from TravelMemory's "places to revisit": an event has one specific
/// occurrence date rather than an open-ended visit history. Brand new type
/// (no legacy on-disk shape to support), so synthesized Codable is fine —
/// unlike TravelMemory, which hand-writes its Codable conformance for
/// backward compatibility.
struct Event: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var date: Date
    var latitude: Double
    var longitude: Double
    var address: String?
    var website: String?
    var photoFilenames: [String]
    var attended: Bool
    let dateAdded: Date

    init(
        id: UUID = UUID(),
        name: String,
        date: Date,
        latitude: Double,
        longitude: Double,
        address: String? = nil,
        website: String? = nil,
        photoFilenames: [String] = [],
        attended: Bool = false,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.website = website
        self.photoFilenames = photoFilenames
        self.attended = attended
        self.dateAdded = dateAdded
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The website as an openable URL, adding https:// when the user omitted a scheme.
    var websiteURL: URL? {
        guard let website, let trimmed = website.trimmedNonEmpty else { return nil }
        let lower = trimmed.lowercased()
        let absolute = (lower.hasPrefix("http://") || lower.hasPrefix("https://")) ? trimmed : "https://" + trimmed
        return URL(string: absolute)
    }

    var coverPhotoFilename: String? {
        photoFilenames.first
    }
}
