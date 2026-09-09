//
//  AdjustLocationView.swift
//  Comebackone day 1.2
//
//  Lets the user drop a pin anywhere on the map and pulls Apple Maps' own
//  data for that point — for correcting a memory whose location is wrong,
//  most often because a photo's embedded GPS doesn't match where the place
//  actually is. A tap resolves to the nearest known business via
//  `LocationSearchService.nearestPlace(to:)` (the same lookup AddMemoryView
//  already uses for a photo's GPS EXIF); if nothing's nearby, falls back to
//  a plain reverse-geocoded address so a bare pin can still be confirmed.
//
//  No other map in this app is tappable — every existing `Map` only
//  intercepts taps on an annotation's own pin subview — so this is the
//  first use of `MapReader` to turn a screen tap into a real coordinate.
//

import SwiftUI
import MapKit
import CoreLocation

/// Everything resolved from a tapped map coordinate, ready to prefill an
/// entry — the same shape of data AddMemoryView's other location-setting
/// paths (search, current-location, photo-GPS) already collect.
struct PinnedLocation {
    let coordinate: CLLocationCoordinate2D
    let name: String?
    let category: Category?
    let address: String?
    let website: String?
    let phoneNumber: String?
}

struct AdjustLocationView: View {
    let initialCoordinate: CLLocationCoordinate2D?
    let onConfirm: (PinnedLocation) -> Void

    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition
    @State private var pinCoordinate: CLLocationCoordinate2D?
    @State private var resolved: PinnedLocation?
    @State private var isResolving = false
    /// Tags each lookup so a slow earlier tap's result can't overwrite a
    /// later, faster one — discarded on completion if it's no longer current.
    @State private var pendingLookupID: UUID?

    init(initialCoordinate: CLLocationCoordinate2D?, onConfirm: @escaping (PinnedLocation) -> Void) {
        self.initialCoordinate = initialCoordinate
        self.onConfirm = onConfirm
        _pinCoordinate = State(initialValue: initialCoordinate)
        if let initialCoordinate {
            _cameraPosition = State(initialValue: .region(Self.region(centeredOn: initialCoordinate)))
        } else {
            _cameraPosition = State(initialValue: .automatic)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        if let pinCoordinate {
                            Marker(resolved?.name ?? "Dropped Pin", coordinate: pinCoordinate)
                        }
                    }
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                            pinCoordinate = coordinate
                            resolve(coordinate)
                        }
                    )
                }
                .ignoresSafeArea(edges: .bottom)

                if pinCoordinate == nil {
                    Text("Tap the map to drop a pin at the correct spot")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.thickMaterial, in: Capsule())
                        .padding(.bottom, 24)
                } else {
                    confirmationStrip
                }
            }
            .navigationTitle("Adjust Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                guard initialCoordinate == nil, let current = locationManager.currentLocation else { return }
                cameraPosition = .region(Self.region(centeredOn: current))
            }
        }
    }

    @ViewBuilder
    private var confirmationStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isResolving {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Looking up this place…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let resolved {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: (resolved.category ?? .location).icon)
                        .foregroundStyle((resolved.category ?? .location).color)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(resolved.name ?? "Dropped Pin")
                            .font(.subheadline.weight(.semibold))
                        if let address = resolved.address {
                            Text(address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                Button {
                    onConfirm(resolved)
                    dismiss()
                } label: {
                    Text(resolved.name == nil ? "Use This Pin" : "Use This Place")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private func resolve(_ coordinate: CLLocationCoordinate2D) {
        let lookupID = UUID()
        pendingLookupID = lookupID
        resolved = nil
        isResolving = true

        Task {
            let place: PinnedLocation
            if let match = await LocationSearchService.nearestPlace(to: coordinate) {
                place = PinnedLocation(
                    coordinate: coordinate,
                    name: match.name,
                    category: Category.from(mapKitCategory: match.mapKitCategory),
                    address: match.address,
                    website: match.website,
                    phoneNumber: match.phoneNumber
                )
            } else {
                let address = await LocationSearchService.address(for: coordinate)
                place = PinnedLocation(
                    coordinate: coordinate,
                    name: nil,
                    category: nil,
                    address: address ?? Self.formattedCoordinate(coordinate),
                    website: nil,
                    phoneNumber: nil
                )
            }

            guard pendingLookupID == lookupID else { return }
            isResolving = false
            resolved = place
        }
    }

    private static func region(centeredOn coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
    }

    private static func formattedCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }
}
