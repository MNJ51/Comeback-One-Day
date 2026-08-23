//
//  GooglePlacesService.swift
//  Comebackone day 1.2
//
//  Thin wrapper around the Google Places API (New) — used for itinerary
//  generation because, unlike MapKit, it actually exposes star ratings,
//  review counts, editorial summaries, and business photos. Requires
//  Secrets.googlePlacesAPIKey; see Secrets.swift.example for setup.
//

import CoreLocation
import Foundation

struct GooglePlace {
    let name: String
    let types: [String]
    let primaryType: String?
    let coordinate: CLLocationCoordinate2D
    let address: String?
    let rating: Double?
    let userRatingCount: Int?
    let phoneNumber: String?
    let website: String?
    let summary: String?
    let photoName: String?
}

enum GooglePlacesService {
    private static let searchURL = URL(string: "https://places.googleapis.com/v1/places:searchNearby")!
    private static let fieldMask = "places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.nationalPhoneNumber,places.websiteUri,places.editorialSummary,places.primaryType,places.types,places.photos"

    /// Searches for places matching any of `includedTypes` within `radiusMeters`
    /// of `center`. Returns an empty array (rather than throwing) on any
    /// failure — missing/invalid API key, no network, bad response — so
    /// callers can fall back gracefully instead of crashing an itinerary.
    static func searchNearby(
        includedTypes: [String],
        center: CLLocationCoordinate2D,
        radiusMeters: Double,
        maxResultCount: Int = 20
    ) async -> [GooglePlace] {
        guard !Secrets.googlePlacesAPIKey.isEmpty else { return [] }

        var request = URLRequest(url: searchURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Secrets.googlePlacesAPIKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")

        let body = SearchNearbyRequest(
            includedTypes: includedTypes,
            maxResultCount: min(maxResultCount, 20),
            locationRestriction: .init(circle: .init(
                center: .init(latitude: center.latitude, longitude: center.longitude),
                radius: min(radiusMeters, 50_000)
            ))
        )
        guard let bodyData = try? JSONEncoder().encode(body) else { return [] }
        request.httpBody = bodyData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(SearchNearbyResponse.self, from: data) else {
            return []
        }

        return (decoded.places ?? []).compactMap(GooglePlace.init(dto:))
    }

    /// Builds a URL that redirects directly to the photo's image bytes —
    /// usable as-is with AsyncImage, no separate download step needed.
    static func photoURL(photoName: String, maxWidthPx: Int = 800) -> URL? {
        guard !Secrets.googlePlacesAPIKey.isEmpty else { return nil }
        var components = URLComponents(string: "https://places.googleapis.com/v1/\(photoName)/media")
        components?.queryItems = [
            URLQueryItem(name: "maxWidthPx", value: String(maxWidthPx)),
            URLQueryItem(name: "key", value: Secrets.googlePlacesAPIKey)
        ]
        return components?.url
    }
}

// MARK: - Request/response wire types

private struct SearchNearbyRequest: Encodable {
    struct LocationRestriction: Encodable {
        struct Circle: Encodable {
            struct LatLng: Encodable { let latitude: Double; let longitude: Double }
            let center: LatLng
            let radius: Double
        }
        let circle: Circle
    }
    let includedTypes: [String]
    let maxResultCount: Int
    let locationRestriction: LocationRestriction
}

private struct SearchNearbyResponse: Decodable {
    let places: [PlaceDTO]?
}

private struct PlaceDTO: Decodable {
    struct LocalizedText: Decodable { let text: String }
    struct LatLng: Decodable { let latitude: Double; let longitude: Double }
    struct Photo: Decodable { let name: String }

    let displayName: LocalizedText?
    let formattedAddress: String?
    let location: LatLng?
    let rating: Double?
    let userRatingCount: Int?
    let nationalPhoneNumber: String?
    let websiteUri: String?
    let editorialSummary: LocalizedText?
    let primaryType: String?
    let types: [String]?
    let photos: [Photo]?
}

private extension GooglePlace {
    init?(dto: PlaceDTO) {
        guard let name = dto.displayName?.text, let location = dto.location else { return nil }
        self.name = name
        self.coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        self.address = dto.formattedAddress
        self.rating = dto.rating
        self.userRatingCount = dto.userRatingCount
        self.phoneNumber = dto.nationalPhoneNumber
        self.website = dto.websiteUri
        self.summary = dto.editorialSummary?.text
        self.primaryType = dto.primaryType
        self.types = dto.types ?? []
        self.photoName = dto.photos?.first?.name
    }
}
