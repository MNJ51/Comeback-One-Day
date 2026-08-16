//
//  LocationSearchService.swift
//  Comebackone day 1.2
//
//  Wraps MKLocalSearchCompleter so the add-memory form can find places by name
//  instead of asking the user to type raw coordinates.
//

import MapKit
import Combine

class LocationSearchService: NSObject, ObservableObject {
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    /// Bias results toward the user's surroundings when we know where they are.
    func focus(around coordinate: CLLocationCoordinate2D) {
        completer.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
    }

    func search(_ query: String) {
        if query.isEmpty {
            results = []
        }
        completer.queryFragment = query
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> (name: String, coordinate: CLLocationCoordinate2D, address: String?)? {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        guard let response = try? await search.start(),
              let item = response.mapItems.first else {
            return nil
        }
        let placemark = item.placemark
        return (item.name ?? completion.title, placemark.coordinate, Self.formattedAddress(from: placemark))
    }

    /// Looks up a human-readable address for a coordinate.
    static func address(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location),
              let placemark = placemarks.first else {
            return nil
        }
        return formattedAddress(from: placemark)
    }

    /// Builds a single-line address from a placemark's components.
    private static func formattedAddress(from placemark: CLPlacemark) -> String? {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        let parts = [street, placemark.locality, placemark.administrativeArea, placemark.postalCode, placemark.country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

extension LocationSearchService: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}
