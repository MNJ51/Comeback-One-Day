//
//  LocationSearchService.swift
//  Comebackone day 1.1
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
        return (item.name ?? completion.title, item.location.coordinate, item.address?.fullAddress)
    }

    /// Looks up a human-readable address for a coordinate.
    static func address(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let items = try? await request.mapItems else {
            return nil
        }
        return items.first?.address?.fullAddress
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
