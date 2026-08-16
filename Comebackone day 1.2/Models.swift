//
//  Models.swift
//  Comebackone day 1.2
//

import SwiftUI
import CoreLocation
import UIKit

enum Category: String, Codable, CaseIterable, Identifiable {
    case restaurant = "Restaurant"
    case bar = "Bar/Pub"
    case hotel = "Hotel"
    case location = "Location"
    case foodMarket = "Food Market"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .restaurant: return .red
        case .bar: return .orange
        case .hotel: return .blue
        case .foodMarket: return .green
        case .location: return .purple
        }
    }

    var icon: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .bar: return "wineglass.fill"
        case .hotel: return "bed.double.fill"
        case .foodMarket: return "basket.fill"
        case .location: return "mappin"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Category(rawValue: raw) ?? .location
    }
}

struct TravelMemory: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var category: Category
    var photoFilenames: [String]
    var address: String?
    /// The business's website, as typed by the user (scheme optional).
    var website: String?
    /// 0 means unrated, otherwise 1–5 stars.
    var rating: Int
    var notes: String
    let dateAdded: Date
    var dateVisited: Date?
    /// True when this place was added by importing someone else's shared deep link.
    var isReceivedFromShare: Bool
    /// The sender's device name, captured when this place was imported from a shared link.
    var senderName: String?

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, category: Category, photoFilenames: [String] = [], address: String? = nil, website: String? = nil, rating: Int = 0, notes: String = "", dateAdded: Date = Date(), dateVisited: Date? = nil, isReceivedFromShare: Bool = false, senderName: String? = nil) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.photoFilenames = photoFilenames
        self.address = address
        self.website = website
        self.rating = rating
        self.notes = notes
        self.dateAdded = dateAdded
        self.dateVisited = dateVisited
        self.isReceivedFromShare = isReceivedFromShare
        self.senderName = senderName
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The photo shown on map pins and list rows.
    var coverPhotoFilename: String? {
        photoFilenames.first
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, category, photoFilenames, photoFilename, address, website, rating, notes, dateAdded, dateVisited, isReceivedFromShare, senderName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        category = try container.decode(Category.self, forKey: .category)
        // Earlier builds stored a single photoFilename.
        if let list = try container.decodeIfPresent([String].self, forKey: .photoFilenames) {
            photoFilenames = list
        } else if let single = try container.decodeIfPresent(String.self, forKey: .photoFilename) {
            photoFilenames = [single]
        } else {
            photoFilenames = []
        }
        address = try container.decodeIfPresent(String.self, forKey: .address)
        website = try container.decodeIfPresent(String.self, forKey: .website)
        rating = try container.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        dateVisited = try container.decodeIfPresent(Date.self, forKey: .dateVisited)
        isReceivedFromShare = try container.decodeIfPresent(Bool.self, forKey: .isReceivedFromShare) ?? false
        senderName = try container.decodeIfPresent(String.self, forKey: .senderName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(category, forKey: .category)
        try container.encode(photoFilenames, forKey: .photoFilenames)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encodeIfPresent(website, forKey: .website)
        try container.encode(rating, forKey: .rating)
        try container.encode(notes, forKey: .notes)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encodeIfPresent(dateVisited, forKey: .dateVisited)
        try container.encode(isReceivedFromShare, forKey: .isReceivedFromShare)
        try container.encodeIfPresent(senderName, forKey: .senderName)
    }
}

extension String {
    /// Trimmed contents, or nil when the field was left blank.
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Sharing places as a deep link

extension TravelMemory {
    /// The website as an openable URL, adding https:// when the user omitted a scheme.
    var websiteURL: URL? {
        guard let website else { return nil }
        let trimmed = website.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        let absolute = (lower.hasPrefix("http://") || lower.hasPrefix("https://"))
            ? trimmed
            : "https://" + trimmed
        return URL(string: absolute)
    }

    static let shareScheme = "comebackoneday"

    /// A deep link another Come Back One Day user can open to import this place.
    /// Photos are not included — links can't carry image data.
    var shareURL: URL? {
        var components = URLComponents()
        components.scheme = Self.shareScheme
        components.host = "add"
        var items = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "cat", value: category.rawValue),
            URLQueryItem(name: "rating", value: String(rating))
        ]
        if let address { items.append(URLQueryItem(name: "addr", value: address)) }
        if let website, !website.isEmpty { items.append(URLQueryItem(name: "web", value: website)) }
        if !notes.isEmpty { items.append(URLQueryItem(name: "notes", value: notes)) }
        if let dateVisited {
            items.append(URLQueryItem(name: "date", value: String(Int(dateVisited.timeIntervalSince1970))))
        }
        // Identifies the sender to whoever imports this link. There's no account
        // system, so the device's own name is the closest thing to "who sent this" —
        // most people's devices are named after themselves (e.g. "Mike's iPhone").
        let senderName = UIDevice.current.name.trimmedNonEmpty
        if let senderName { items.append(URLQueryItem(name: "from", value: senderName)) }
        components.queryItems = items
        return components.url
    }

    /// Builds a new place (fresh id, no photos) from a shared deep link.
    init?(shareURL url: URL) {
        guard url.scheme == Self.shareScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "add" else { return nil }
        let query = components.queryItems ?? []
        func value(_ key: String) -> String? { query.first { $0.name == key }?.value }
        guard let name = value("name"), !name.isEmpty,
              let lat = value("lat").flatMap(Double.init),
              let lon = value("lon").flatMap(Double.init) else { return nil }
        self.init(
            name: name,
            latitude: lat,
            longitude: lon,
            category: Category(rawValue: value("cat") ?? "") ?? .location,
            photoFilenames: [],
            address: value("addr"),
            website: value("web"),
            rating: Int(value("rating") ?? "") ?? 0,
            notes: value("notes") ?? "",
            dateVisited: value("date").flatMap(Double.init).map { Date(timeIntervalSince1970: $0) },
            isReceivedFromShare: true,
            senderName: value("from")
        )
    }
}
