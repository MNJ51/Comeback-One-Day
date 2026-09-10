//
//  EventDetailView.swift
//  Comebackone day 1.2
//

import SwiftUI
import MapKit

struct EventDetailView: View {
    let eventID: UUID
    @EnvironmentObject var eventStore: EventStore
    @Environment(\.dismiss) var dismiss

    @State private var showingEdit = false
    @State private var showingDeleteConfirmation = false
    @State private var showingShare = false
    @State private var showingPhotoViewer = false
    @State private var photoViewerStartIndex = 0

    private var event: Event? {
        eventStore.event(withID: eventID)
    }

    var body: some View {
        NavigationStack {
            if let event {
                ScrollView {
                    VStack(spacing: 20) {
                        if !event.photoFilenames.isEmpty {
                            TabView {
                                ForEach(Array(event.photoFilenames.enumerated()), id: \.offset) { index, filename in
                                    if let uiImage = PhotoStore.thumbnail(for: filename, maxDimension: 400) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(maxWidth: .infinity)
                                            .clipped()
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                photoViewerStartIndex = index
                                                showingPhotoViewer = true
                                            }
                                    }
                                }
                            }
                            .tabViewStyle(.page)
                            .frame(height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                        }

                        VStack(alignment: .leading, spacing: 15) {
                            Text(event.name)
                                .font(.title)
                                .bold()

                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundStyle(.purple)
                                Text(event.date, style: .date)
                                    .foregroundStyle(.secondary)

                                if event.attended {
                                    Text("Attended")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.green.opacity(0.2))
                                        .foregroundStyle(.green)
                                        .clipShape(Capsule())
                                }
                            }

                            if let address = event.address {
                                HStack(alignment: .top) {
                                    Image(systemName: "mappin.and.ellipse")
                                    Text(address)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let websiteURL = event.websiteURL {
                                HStack(alignment: .top) {
                                    Image(systemName: "globe")
                                    Link(event.website ?? websiteURL.absoluteString, destination: websiteURL)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }

                            Map(position: .constant(.region(MKCoordinateRegion(
                                center: event.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            )))) {
                                Marker(event.name, coordinate: event.coordinate)
                            }
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .allowsHitTesting(false)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                        VStack(spacing: 12) {
                            Text("Get Directions")
                                .font(.headline)
                                .padding(.top)

                            HStack(spacing: 15) {
                                DirectionButton(icon: "car.fill", label: "Drive", color: .blue) {
                                    openMaps(event: event, mode: MKLaunchOptionsDirectionsModeDriving)
                                }

                                DirectionButton(icon: "figure.walk", label: "Walk", color: .green) {
                                    openMaps(event: event, mode: MKLaunchOptionsDirectionsModeWalking)
                                }

                                DirectionButton(icon: "bus.fill", label: "Transit", color: .purple) {
                                    openMaps(event: event, mode: MKLaunchOptionsDirectionsModeTransit)
                                }
                            }
                        }
                        .padding()

                        Button {
                            var updated = event
                            updated.attended.toggle()
                            eventStore.update(updated)
                        } label: {
                            Label(
                                event.attended ? "Mark Not Attended" : "Mark Attended",
                                systemImage: event.attended ? "xmark.circle" : "checkmark.circle"
                            )
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.green)
                        }
                        .padding(.horizontal)

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Event", systemImage: "trash")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    .padding()
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingShare = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(action: {
                                showingEdit = true
                            }) {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive, action: {
                                showingDeleteConfirmation = true
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .sheet(isPresented: $showingEdit) {
                    EditEventView(event: event)
                }
                .sheet(isPresented: $showingShare) {
                    ShareSheet(items: shareItems(for: event))
                }
                .fullScreenCover(isPresented: $showingPhotoViewer) {
                    PhotoViewerView(filenames: event.photoFilenames, currentIndex: photoViewerStartIndex)
                }
                .confirmationDialog(
                    "Delete \(event.name)?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        eventStore.delete(event)
                        dismiss()
                    }
                } message: {
                    Text("This event and its photos will be removed.")
                }
            }
        }
    }

    private func shareItems(for event: Event) -> [Any] {
        var items: [Any] = []
        if let image = PhotoStore.image(for: event.coverPhotoFilename) {
            items.append(image)
        }
        items.append(shareText(for: event))
        return items
    }

    private func shareText(for event: Event) -> String {
        var lines = [event.name]
        lines.append(event.date.formatted(date: .abbreviated, time: .omitted))
        if let address = event.address {
            lines.append(address)
        }
        if let websiteURL = event.websiteURL {
            lines.append(websiteURL.absoluteString)
        }
        lines.append("https://maps.apple.com/?ll=\(event.latitude),\(event.longitude)&q=\(event.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? event.name)")
        return lines.joined(separator: "\n")
    }

    private func openMaps(event: Event, mode: String) {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: event.coordinate))
        mapItem.name = event.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
    }
}
