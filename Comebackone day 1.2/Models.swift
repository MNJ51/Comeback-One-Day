//
//  Models.swift
//  Comebackone day 1.2
//

import SwiftUI
import CoreLocation
import UIKit

enum Category: String, Codable, CaseIterable, Identifiable {
    case restaurant = "Restaurant"
    case glutenFree = "Gluten Free"
    case cafe = "Cafe"
    case bar = "Bar/Pub"
    case hotel = "Hotel"
    case location = "Location"
    case foodMarket = "Food Market"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .restaurant: return .red
        case .glutenFree: return .mint
        case .cafe: return .brown
        case .bar: return .orange
        case .hotel: return .blue
        case .foodMarket: return .green
        case .location: return .purple
        }
    }

    var icon: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .glutenFree: return "leaf.fill"
        case .cafe: return "cup.and.saucer.fill"
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

enum VisitStatus: String, Codable, CaseIterable, Identifiable {
    case beenThere = "Been There"
    case wantToGo = "Want to Go"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = VisitStatus(rawValue: raw) ?? .beenThere
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
    /// The business's phone number, as typed by the user or auto-filled from search.
    var phoneNumber: String?
    /// 0 means unrated, otherwise 1–5 stars.
    var rating: Int
    var notes: String
    let dateAdded: Date
    var dateVisited: Date?
    /// True when this place was added by importing someone else's shared deep link.
    var isReceivedFromShare: Bool
    /// The sender's device name, captured when this place was imported from a shared link.
    var senderName: String?
    /// Groups this place into a trip or city collection, e.g. "Greece 2026".
    var tripName: String?
    /// A recorded voice memo about this place; the filename of an .m4a in VoiceNoteStore.
    var voiceNoteFilename: String?
    /// Whether this is somewhere already visited (the app's original premise) or
    /// a wishlist place not yet been to. Defaults to .beenThere for old data, since
    /// that's what every place meant before this field existed.
    var visitStatus: VisitStatus

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, category: Category, photoFilenames: [String] = [], address: String? = nil, website: String? = nil, phoneNumber: String? = nil, rating: Int = 0, notes: String = "", dateAdded: Date = Date(), dateVisited: Date? = nil, isReceivedFromShare: Bool = false, senderName: String? = nil, tripName: String? = nil, voiceNoteFilename: String? = nil, visitStatus: VisitStatus = .beenThere) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.photoFilenames = photoFilenames
        self.address = address
        self.website = website
        self.phoneNumber = phoneNumber
        self.rating = rating
        self.notes = notes
        self.dateAdded = dateAdded
        self.dateVisited = dateVisited
        self.isReceivedFromShare = isReceivedFromShare
        self.senderName = senderName
        self.tripName = tripName
        self.voiceNoteFilename = voiceNoteFilename
        self.visitStatus = visitStatus
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The country, read off the end of the stored address (LocationSearchService
    /// always appends it last: "street, suburb, state, postcode, country").
    var country: String? {
        guard let last = address?.split(separator: ",").last else { return nil }
        return String(last).trimmingCharacters(in: .whitespaces).trimmedNonEmpty
    }

    /// The photo shown on map pins and list rows.
    var coverPhotoFilename: String? {
        photoFilenames.first
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, category, photoFilenames, photoFilename, address, website, phoneNumber, rating, notes, dateAdded, dateVisited, isReceivedFromShare, senderName, tripName, voiceNoteFilename, visitStatus
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
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        rating = try container.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        dateVisited = try container.decodeIfPresent(Date.self, forKey: .dateVisited)
        isReceivedFromShare = try container.decodeIfPresent(Bool.self, forKey: .isReceivedFromShare) ?? false
        senderName = try container.decodeIfPresent(String.self, forKey: .senderName)
        tripName = try container.decodeIfPresent(String.self, forKey: .tripName)
        voiceNoteFilename = try container.decodeIfPresent(String.self, forKey: .voiceNoteFilename)
        visitStatus = try container.decodeIfPresent(VisitStatus.self, forKey: .visitStatus) ?? .beenThere
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
        try container.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        try container.encode(rating, forKey: .rating)
        try container.encode(notes, forKey: .notes)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encodeIfPresent(dateVisited, forKey: .dateVisited)
        try container.encode(isReceivedFromShare, forKey: .isReceivedFromShare)
        try container.encodeIfPresent(senderName, forKey: .senderName)
        try container.encodeIfPresent(tripName, forKey: .tripName)
        try container.encodeIfPresent(voiceNoteFilename, forKey: .voiceNoteFilename)
        try container.encode(visitStatus, forKey: .visitStatus)
    }
}

extension String {
    /// Trimmed contents, or nil when the field was left blank.
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension TravelMemory {
    /// True when this place was saved on this same month/day in an earlier year —
    /// a "you were here a year ago today" flashback. Never true for something
    /// saved earlier this same year (that's just "recent," not a flashback).
    func isOnThisDay(relativeTo now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let referenceDate = dateVisited ?? dateAdded
        let nowYear = calendar.component(.year, from: now)
        let refYear = calendar.component(.year, from: referenceDate)
        guard refYear != nowYear else { return false }
        return calendar.component(.month, from: referenceDate) == calendar.component(.month, from: now)
            && calendar.component(.day, from: referenceDate) == calendar.component(.day, from: now)
    }

    /// How many years ago the reference date (dateVisited, falling back to
    /// dateAdded) was, for "N years ago today" copy.
    func yearsAgo(relativeTo now: Date = Date(), calendar: Calendar = .current) -> Int? {
        let referenceDate = dateVisited ?? dateAdded
        return calendar.dateComponents([.year], from: referenceDate, to: now).year
    }

    /// The phone number as a tappable tel: URL, stripped of everything a dialer
    /// doesn't need (spaces, parens, dashes) while keeping a leading "+".
    var phoneCallURL: URL? {
        guard let phoneNumber, let trimmed = phoneNumber.trimmedNonEmpty else { return nil }
        let dialable = trimmed.filter { $0.isNumber || $0 == "+" }
        guard !dialable.isEmpty else { return nil }
        return URL(string: "tel:\(dialable)")
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
    static let shareHosts = ["www.thehealthclubonline.com", "thehealthclubonline.com"]
    static let sharePath = "/comebackonedayapp/add"

    /// A deep link another Come Back One Day user can open to import this place.
    /// Photos are not included — links can't carry image data. This is a
    /// Universal Link (not the older comebackoneday:// scheme) so it also works
    /// as a plain webpage — landing on the download page — for anyone who
    /// doesn't have the app installed yet.
    var shareURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.shareHosts[0]
        components.path = Self.sharePath
        var items = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "cat", value: category.rawValue),
            URLQueryItem(name: "rating", value: String(rating))
        ]
        if let address { items.append(URLQueryItem(name: "addr", value: address)) }
        if let website, !website.isEmpty { items.append(URLQueryItem(name: "web", value: website)) }
        if let phoneNumber, !phoneNumber.isEmpty { items.append(URLQueryItem(name: "phone", value: phoneNumber)) }
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

    /// Builds a new place (fresh id, no photos) from a shared deep link — either
    /// the current Universal Link (https://.../comebackonedayapp/add?...) or the
    /// older comebackoneday://add?... scheme from links shared before that existed.
    init?(shareURL url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let isLegacyScheme = url.scheme == Self.shareScheme && components.host == "add"
        let isUniversalLink = url.scheme == "https"
            && Self.shareHosts.contains(components.host ?? "")
            && components.path == Self.sharePath
        guard isLegacyScheme || isUniversalLink else { return nil }
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
            phoneNumber: value("phone"),
            rating: Int(value("rating") ?? "") ?? 0,
            notes: value("notes") ?? "",
            dateVisited: value("date").flatMap(Double.init).map { Date(timeIntervalSince1970: $0) },
            isReceivedFromShare: true,
            senderName: value("from")
        )
    }
}
