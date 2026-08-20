//
//  MemoryDetailView.swift
//  Comebackone day 1.2
//

import SwiftUI
import MapKit

struct MemoryDetailView: View {
    let memoryID: UUID
    @EnvironmentObject var store: MemoryStore
    @Environment(\.dismiss) var dismiss

    @State private var showingEdit = false
    @State private var showingDeleteConfirmation = false
    @State private var showingShare = false
    @State private var showingPhotoViewer = false
    @State private var photoViewerStartIndex = 0

    private var memory: TravelMemory? {
        store.memory(withID: memoryID)
    }

    var body: some View {
        NavigationStack {
            if let memory {
                ScrollView {
                    VStack(spacing: 20) {
                        if !memory.photoFilenames.isEmpty {
                            TabView {
                                ForEach(Array(memory.photoFilenames.enumerated()), id: \.offset) { index, filename in
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
                            Text(memory.name)
                                .font(.title)
                                .bold()

                            StarRatingLabel(rating: memory.rating)

                            HStack {
                                Image(systemName: "tag.fill")
                                    .foregroundStyle(memory.category.color)
                                Text(memory.category.rawValue)
                                    .foregroundStyle(.secondary)

                                if memory.visitStatus == .wantToGo {
                                    Text("Want to Go")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.yellow.opacity(0.2))
                                        .foregroundStyle(.orange)
                                        .clipShape(Capsule())
                                }
                            }

                            if let tripName = memory.tripName {
                                HStack {
                                    Image(systemName: "airplane")
                                        .foregroundStyle(Color.accentColor)
                                    Text(tripName)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if memory.isReceivedFromShare, let senderName = memory.senderName {
                                HStack {
                                    Image(systemName: "person.crop.circle.fill")
                                        .foregroundStyle(.yellow)
                                    Text("Shared by \(senderName)")
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let address = memory.address {
                                HStack(alignment: .top) {
                                    Image(systemName: "mappin.and.ellipse")
                                    Text(address)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let websiteURL = memory.websiteURL {
                                HStack(alignment: .top) {
                                    Image(systemName: "globe")
                                    Link(memory.website ?? websiteURL.absoluteString,
                                         destination: websiteURL)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }

                            if let phoneCallURL = memory.phoneCallURL, let phoneNumber = memory.phoneNumber {
                                HStack(alignment: .top) {
                                    Image(systemName: "phone.fill")
                                    Link(phoneNumber, destination: phoneCallURL)
                                }
                            }

                            if let dateVisited = memory.dateVisited {
                                HStack {
                                    Image(systemName: "calendar")
                                    Text("Visited: \(dateVisited, style: .date)")
                                        .foregroundStyle(.secondary)
                                }
                            }

                            HStack {
                                Image(systemName: "clock")
                                Text("Added: \(memory.dateAdded, style: .date)")
                                    .foregroundStyle(.secondary)
                            }

                            if !memory.notes.isEmpty {
                                Text(memory.notes)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                            }

                            if let voiceNoteFilename = memory.voiceNoteFilename {
                                VoiceNotePlaybackRow(filename: voiceNoteFilename)
                                    .padding(12)
                                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                        VStack(spacing: 12) {
                            Text("Get Directions")
                                .font(.headline)
                                .padding(.top)

                            HStack(spacing: 15) {
                                DirectionButton(icon: "car.fill", label: "Drive", color: .blue) {
                                    openMaps(memory: memory, mode: MKLaunchOptionsDirectionsModeDriving)
                                }

                                DirectionButton(icon: "figure.walk", label: "Walk", color: .green) {
                                    openMaps(memory: memory, mode: MKLaunchOptionsDirectionsModeWalking)
                                }

                                DirectionButton(icon: "bicycle", label: "Bike", color: .orange) {
                                    openCyclingDirections(memory: memory)
                                }

                                DirectionButton(icon: "bus.fill", label: "Transit", color: .purple) {
                                    openMaps(memory: memory, mode: MKLaunchOptionsDirectionsModeTransit)
                                }
                            }
                        }
                        .padding()

                        VStack(spacing: 8) {
                            Button {
                                openTripAdvisorReview(for: memory)
                            } label: {
                                Label("Write a Review on TripAdvisor", systemImage: "star.bubble.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(.green)
                            }

                            Text("Opens TripAdvisor's search for this place and copies your rating and notes so you can paste them into the review.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal)

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Place", systemImage: "trash")
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
                        Button("Close") {
                            dismiss()
                        }
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
                    EditMemoryView(memory: memory)
                }
                .sheet(isPresented: $showingShare) {
                    ShareSheet(items: shareItems(for: memory))
                }
                .fullScreenCover(isPresented: $showingPhotoViewer) {
                    PhotoViewerView(filenames: memory.photoFilenames, currentIndex: photoViewerStartIndex)
                }
                .task(id: memoryID) {
                    await fetchAddressIfNeeded()
                }
                .confirmationDialog(
                    "Delete \(memory.name)?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        store.delete(memory)
                        dismiss()
                    }
                } message: {
                    Text("This memory and its photo will be removed.")
                }
            }
        }
    }

    /// Items handed to the system share sheet: the cover photo (if any) plus text.
    private func shareItems(for memory: TravelMemory) -> [Any] {
        var items: [Any] = []
        if let image = PhotoStore.image(for: memory.coverPhotoFilename) {
            items.append(image)
        }
        items.append(shareText(for: memory))
        return items
    }

    private func shareText(for memory: TravelMemory) -> String {
        var lines = [memory.name]
        if memory.rating > 0 {
            lines.append(String(repeating: "★", count: memory.rating))
        }
        if let address = memory.address {
            lines.append(address)
        }
        if let websiteURL = memory.websiteURL {
            lines.append(websiteURL.absoluteString)
        }
        if let phoneNumber = memory.phoneNumber {
            lines.append(phoneNumber)
        }
        if !memory.notes.isEmpty {
            lines.append(memory.notes)
        }
        lines.append("https://maps.apple.com/?ll=\(memory.latitude),\(memory.longitude)&q=\(memory.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? memory.name)")
        if let shareURL = memory.shareURL {
            lines.append("Add to Come Back One Day: \(shareURL.absoluteString)")
        }
        return lines.joined(separator: "\n")
    }

    // Memories created before address support (or via Quick Camera) look up
    // their address the first time they're viewed, then keep it.
    private func fetchAddressIfNeeded() async {
        guard var memory = store.memory(withID: memoryID), memory.address == nil else { return }
        guard let address = await LocationSearchService.address(for: memory.coordinate) else { return }
        memory.address = address
        store.update(memory)
    }

    private func openMaps(memory: TravelMemory, mode: String) {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: memory.coordinate))
        mapItem.name = memory.name

        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
    }

    // Apple Maps has no cycling launch option, so use the maps.apple.com
    // URL scheme where dirflg=c requests cycling directions.
    private func openCyclingDirections(memory: TravelMemory) {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "daddr", value: "\(memory.latitude),\(memory.longitude)"),
            URLQueryItem(name: "dirflg", value: "c")
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }

    // TripAdvisor has no API for submitting a review, and every review is
    // tied to the reviewer's own TripAdvisor account regardless — there's no
    // way for this (or any) third-party app to post one on the user's behalf.
    // The closest honest equivalent: land them on the right listing to write
    // it themselves, with their rating/notes copied so they're not retyping.
    private func openTripAdvisorReview(for memory: TravelMemory) {
        var clipboardLines: [String] = []
        if memory.rating > 0 {
            clipboardLines.append(String(repeating: "★", count: memory.rating))
        }
        if !memory.notes.isEmpty {
            clipboardLines.append(memory.notes)
        }
        if !clipboardLines.isEmpty {
            UIPasteboard.general.string = clipboardLines.joined(separator: "\n\n")
        }

        var query = memory.name
        if let address = memory.address, !address.isEmpty {
            query += " \(address)"
        }
        var components = URLComponents(string: "https://www.tripadvisor.com/Search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }
}

/// Presents the system share sheet with arbitrary items (photo + text).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Play/pause control with a scrubber-free progress readout for a saved voice note.
struct VoiceNotePlaybackRow: View {
    let filename: String
    @StateObject private var player = VoiceNotePlayer()

    var body: some View {
        HStack {
            Button {
                player.load(filename: filename)
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Voice Note")
                    .font(.subheadline.weight(.medium))
                Text(formattedTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()
        }
        .onAppear { player.load(filename: filename) }
    }

    private var formattedTime: String {
        let time = player.isPlaying || player.currentTime > 0 ? player.currentTime : player.duration
        let seconds = Int(time.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct DirectionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption)
            }
            .frame(width: 70, height: 70)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
