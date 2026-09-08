//
//  JournalMapView.swift
//  Comebackone day 1.2
//
//  All journal entries that have a location, plotted on one map — mirrors
//  MapTabView's own Map/Annotation pattern (ContentView.swift), simplified
//  since journal pins don't need thumbnail/wishlist variants. Uses
//  `.automatic` camera positioning rather than any custom bounding-box math,
//  the same approach ItineraryRouteMapView already relies on to fit a map to
//  a set of annotations.
//

import MapKit
import SwiftUI

struct JournalMapView: View {
    @EnvironmentObject var journalStore: JournalStore
    @EnvironmentObject var store: MemoryStore
    @EnvironmentObject var locationManager: LocationManager
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedEntry: JournalEntry?

    private var entriesWithLocation: [JournalEntry] {
        journalStore.entries.filter { $0.coordinate != nil }
    }

    var body: some View {
        Group {
            if entriesWithLocation.isEmpty {
                ContentUnavailableView(
                    "No Located Entries Yet",
                    systemImage: "map",
                    description: Text("Entries written with location access on will show up here.")
                )
            } else {
                Map(position: $cameraPosition) {
                    ForEach(entriesWithLocation) { entry in
                        Annotation(entry.locationLabel ?? "Journal Entry", coordinate: entry.coordinate!) {
                            JournalMapPin(entry: entry)
                                .onTapGesture {
                                    selectedEntry = entry
                                }
                        }
                    }
                }
                .mapStyle(.standard)
            }
        }
        .navigationTitle("Places")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedEntry) { entry in
            JournalEntryFormSheet(entry: entry)
                .environmentObject(journalStore)
                .environmentObject(store)
                .environmentObject(locationManager)
        }
    }
}

private struct JournalMapPin: View {
    let entry: JournalEntry

    var body: some View {
        Group {
            if let thumbnail = PhotoStore.thumbnail(for: entry.coverPhotoFilename, maxDimension: 40) ?? DrawingStore.thumbnail(for: entry.drawingFilename, maxDimension: 40) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            } else {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 26, height: 26)
                    if let mood = entry.mood {
                        Text(mood.emoji)
                            .font(.caption2)
                    } else {
                        Image(systemName: "book.closed.fill")
                            .font(.caption2)
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .shadow(radius: 2)
    }
}
