//
//  EventListView.swift
//  Comebackone day 1.2
//
//  Bucket-list view for events (concerts, festivals, etc.) the user wants
//  to attend — two fixed sections rather than MemoryListView's dynamic
//  trip-name grouping: Upcoming (soonest first, so "what's next" is always
//  at the top) and Attended (most recently attended first).
//

import SwiftUI

struct EventListView: View {
    @EnvironmentObject var eventStore: EventStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedEvent: Event?
    @State private var showingAddEvent = false

    private var upcomingEvents: [Event] {
        eventStore.events.filter { !$0.attended }.sorted { $0.date < $1.date }
    }

    private var attendedEvents: [Event] {
        eventStore.events.filter(\.attended).sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if eventStore.events.isEmpty {
                    ContentUnavailableView(
                        "No Events Yet",
                        systemImage: "ticket",
                        description: Text("Add an event you want to go to.")
                    )
                } else {
                    List {
                        if !upcomingEvents.isEmpty {
                            Section("Upcoming") {
                                ForEach(upcomingEvents) { event in
                                    Button {
                                        selectedEvent = event
                                    } label: {
                                        EventRow(event: event)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .onDelete { offsets in delete(offsets, from: upcomingEvents) }
                            }
                        }

                        if !attendedEvents.isEmpty {
                            Section("Attended") {
                                ForEach(attendedEvents) { event in
                                    Button {
                                        selectedEvent = event
                                    } label: {
                                        EventRow(event: event)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .onDelete { offsets in delete(offsets, from: attendedEvents) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Event Bucket List")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await eventStore.syncNow()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddEvent = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $selectedEvent) { event in
                EventDetailView(eventID: event.id)
            }
            .sheet(isPresented: $showingAddEvent) {
                AddEventView()
                    .environmentObject(eventStore)
            }
        }
    }

    private func delete(_ offsets: IndexSet, from sectionEvents: [Event]) {
        for index in offsets {
            eventStore.delete(sectionEvents[index])
        }
    }
}

struct EventRow: View {
    let event: Event

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnail = PhotoStore.thumbnail(for: event.coverPhotoFilename, maxDimension: 50) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "ticket.fill")
                    .font(.title3)
                    .foregroundStyle(.purple)
                    .frame(width: 50, height: 50)
                    .background(Color.purple.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(event.name)
                    .font(.headline)

                Text(event.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let address = event.address {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption2)
                        Text(address)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if event.attended {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
