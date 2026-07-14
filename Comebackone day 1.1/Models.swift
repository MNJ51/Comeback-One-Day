//
//  Models.swift
//  Comebackone day 1.1
//

import SwiftUI
import CoreLocation

enum Category: String, Codable, CaseIterable, Identifiable {
    case restaurant = "Restaurant"
    case hotel = "Hotel"
    case location = "Location"
    case foodMarket = "Food Market"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .restaurant: return .red
        case .hotel: return .blue
        case .foodMarket: return .green
        case .location: return .purple
        }
    }

    var icon: String {
        switch self {
        case .restaurant: return "fork.knife"
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
    /// 0 means unrated, otherwise 1–5 stars.
    var rating: Int
    var notes: String
    let dateAdded: Date
    var dateVisited: Date?

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, category: Category, photoFilenames: [String] = [], address: String? = nil, rating: Int = 0, notes: String = "", dateAdded: Date = Date(), dateVisited: Date? = nil) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.photoFilenames = photoFilenames
        self.address = address
        self.rating = rating
        self.notes = notes
        self.dateAdded = dateAdded
        self.dateVisited = dateVisited
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The photo shown on map pins and list rows.
    var coverPhotoFilename: String? {
        photoFilenames.first
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, category, photoFilenames, photoFilename, address, rating, notes, dateAdded, dateVisited
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
        rating = try container.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        dateVisited = try container.decodeIfPresent(Date.self, forKey: .dateVisited)
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
        try container.encode(rating, forKey: .rating)
        try container.encode(notes, forKey: .notes)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encodeIfPresent(dateVisited, forKey: .dateVisited)
    }
}
