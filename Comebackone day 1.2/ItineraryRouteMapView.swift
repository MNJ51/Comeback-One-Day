//
//  ItineraryRouteMapView.swift
//  Comebackone day 1.2
//
//  A map view of a generated itinerary: numbered markers for every stop plus
//  the sequence connecting them, computed live via MKDirections for whichever
//  travel mode the itinerary was generated with (walking, driving, or public
//  transport) — free, no API key, same MapKit system that already powers the
//  rest of this app.
//
//  Adventure-vibe stops especially (hiking trails, campgrounds, kayak/surf
//  spots) often aren't reachable via Apple's road-based directions at all —
//  MKDirections legitimately has no route for a trailhead or a stretch of
//  coastline. Silently dropping those legs left the map showing disconnected
//  pins with no visible order. Every leg is now guaranteed to draw something:
//  a real route where MKDirections has one, a dashed straight line where it
//  doesn't — so the sequence is always visible, for every vibe.
//

import MapKit
import SwiftUI

struct ItineraryRouteMapView: View {
    let stops: [ItineraryStop]
    let origin: CLLocationCoordinate2D
    let travelMode: ItineraryTravelMode

    @Environment(\.dismiss) private var dismiss
    @State private var routeLegs: [RouteLeg] = []
    @State private var isLoadingRoutes = true
    @State private var hasApproximateLegs = false
    @State private var cameraPosition: MapCameraPosition = .automatic

    private enum RouteLeg {
        case real(MKRoute)
        case straightLine(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D)
    }

    /// Only stops the user has actually revealed can be routed to — a
    /// not-yet-tapped Mystery Stop stays a surprise, so it's left off the map.
    private var revealedStops: [ItineraryStop] {
        stops.filter { !$0.isMysteryStop }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    Annotation("Start", coordinate: origin) {
                        Image(systemName: "location.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .background(.white, in: Circle())
                    }

                    ForEach(Array(revealedStops.enumerated()), id: \.element.id) { index, stop in
                        Annotation(stop.place.name, coordinate: stop.place.coordinate) {
                            ZStack {
                                Circle()
                                    .fill(stop.place.category.color)
                                    .frame(width: 28, height: 28)
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            .shadow(radius: 2)
                        }
                    }

                    ForEach(Array(routeLegs.enumerated()), id: \.offset) { _, leg in
                        switch leg {
                        case .real(let route):
                            MapPolyline(route.polyline)
                                .stroke(.blue, lineWidth: 4)
                        case .straightLine(let from, let to):
                            MapPolyline(coordinates: [from, to])
                                .stroke(.blue, style: StrokeStyle(lineWidth: 3, dash: [7, 6]))
                        }
                    }
                }
                .mapStyle(.standard)

                if isLoadingRoutes {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Working out the route…")
                    }
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.thickMaterial, in: Capsule())
                    .padding(.bottom, 20)
                } else if hasApproximateLegs {
                    Text("Dashed legs are a straight line, not a real \(travelMode.rawValue.lowercased()) route — MapKit doesn't have road/path directions for that stretch.")
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.thickMaterial, in: Capsule())
                        .padding(.bottom, 20)
                }
            }
            .navigationTitle("Route Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await loadRoutes()
            }
        }
    }

    /// Computes one leg per consecutive pair of stops (origin → stop 1 → stop
    /// 2 → …), concurrently — MapKit's public API has no multi-waypoint
    /// solver, so a full route is built leg by leg. Every leg resolves to
    /// something drawable: a real route, or a straight line when MKDirections
    /// has none (common for trailheads, beaches, and other off-road stops).
    private func loadRoutes() async {
        let points = [origin] + revealedStops.map { $0.place.coordinate }
        guard points.count > 1 else {
            isLoadingRoutes = false
            return
        }

        let legs = await withTaskGroup(of: (Int, RouteLeg).self) { group in
            for index in 0..<(points.count - 1) {
                group.addTask {
                    let request = MKDirections.Request()
                    request.source = MKMapItem(placemark: MKPlacemark(coordinate: points[index]))
                    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: points[index + 1]))
                    request.transportType = travelMode.mkDirectionsTransportType
                    let response = try? await MKDirections(request: request).calculate()
                    if let route = response?.routes.first {
                        return (index, RouteLeg.real(route))
                    }
                    return (index, RouteLeg.straightLine(from: points[index], to: points[index + 1]))
                }
            }
            var ordered = [RouteLeg?](repeating: nil, count: points.count - 1)
            for await (index, leg) in group {
                ordered[index] = leg
            }
            return ordered.compactMap { $0 }
        }

        routeLegs = legs
        hasApproximateLegs = legs.contains {
            if case .straightLine = $0 { return true }
            return false
        }
        isLoadingRoutes = false
    }
}
