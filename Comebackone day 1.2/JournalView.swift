//
//  JournalView.swift
//  Comebackone day 1.2
//

import SwiftUI

struct JournalListView: View {
    @EnvironmentObject var journalStore: JournalStore
    @EnvironmentObject var store: MemoryStore
    @State private var showingAddEntry = false
    @State private var selectedEntry: JournalEntry?

    private var sortedEntries: [JournalEntry] {
        journalStore.entries.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if journalStore.entries.isEmpty {
                    ContentUnavailableView(
                        "No Journal Entries Yet",
                        systemImage: "book.closed",
                        description: Text("Tap + to write about your day.")
                    )
                } else {
                    List {
                        ForEach(sortedEntries) { entry in
                            Button {
                                selectedEntry = entry
                            } label: {
                                JournalEntryRow(entry: entry, linkedMemory: linkedMemory(for: entry))
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: delete)
                    }
                    .refreshable {
                        await journalStore.syncNow()
                    }
                }
            }
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddEntry) {
                JournalEntryFormSheet(entry: nil)
            }
            .sheet(item: $selectedEntry) { entry in
                JournalEntryFormSheet(entry: entry)
            }
        }
    }

    private func linkedMemory(for entry: JournalEntry) -> TravelMemory? {
        guard let id = entry.linkedMemoryID else { return nil }
        return store.memory(withID: id)
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            journalStore.delete(sortedEntries[index])
        }
    }
}

struct JournalEntryRow: View {
    let entry: JournalEntry
    let linkedMemory: TravelMemory?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.date, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !entry.text.isEmpty {
                Text(entry.text)
                    .font(.body)
                    .lineLimit(3)
            }

            if let linkedMemory {
                HStack(spacing: 4) {
                    Image(systemName: linkedMemory.category.icon)
                        .font(.caption2)
                    Text(linkedMemory.name)
                        .font(.caption)
                }
                .foregroundStyle(linkedMemory.category.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(linkedMemory.category.color.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Add or edit a journal entry, with an optional link to a saved place.
/// `prefilledMemoryID` pre-links a new entry when opened from that place's
/// own detail screen.
struct JournalEntryFormSheet: View {
    let entry: JournalEntry?
    @EnvironmentObject var journalStore: JournalStore
    @EnvironmentObject var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var text: String
    @State private var linkedMemoryID: UUID?
    @State private var showingPlacePicker = false

    init(entry: JournalEntry?, prefilledMemoryID: UUID? = nil) {
        self.entry = entry
        _date = State(initialValue: entry?.date ?? Date())
        _text = State(initialValue: entry?.text ?? "")
        _linkedMemoryID = State(initialValue: entry?.linkedMemoryID ?? prefilledMemoryID)
    }

    private var linkedMemory: TravelMemory? {
        guard let linkedMemoryID else { return nil }
        return store.memory(withID: linkedMemoryID)
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("What happened today?", text: $text, axis: .vertical)
                        .lineLimit(5...12)
                }

                Section {
                    Button {
                        showingPlacePicker = true
                    } label: {
                        HStack {
                            Label(linkedMemory?.name ?? "Link a Place", systemImage: "mappin.circle")
                            Spacer()
                            if linkedMemory != nil {
                                Text("Change")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if linkedMemory != nil {
                        Button("Remove Link", role: .destructive) {
                            linkedMemoryID = nil
                        }
                    }
                } footer: {
                    Text("Optionally link this entry to one of your saved places.")
                }

                if entry != nil {
                    Section {
                        Button("Delete Entry", role: .destructive) {
                            if let entry {
                                journalStore.delete(entry)
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(entry == nil ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingPlacePicker) {
                LinkedPlacePicker(selectedMemoryID: $linkedMemoryID)
            }
        }
    }

    private func save() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let entry {
            var updated = entry
            updated.date = date
            updated.text = trimmedText
            updated.linkedMemoryID = linkedMemoryID
            journalStore.update(updated)
        } else {
            journalStore.add(JournalEntry(date: date, text: trimmedText, linkedMemoryID: linkedMemoryID))
        }
        dismiss()
    }
}

/// Searchable list of saved places to link a journal entry to.
private struct LinkedPlacePicker: View {
    @Binding var selectedMemoryID: UUID?
    @EnvironmentObject var store: MemoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredMemories: [TravelMemory] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.memories }
        return store.memories.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filteredMemories) { memory in
                Button {
                    selectedMemoryID = memory.id
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: memory.category.icon)
                            .foregroundStyle(memory.category.color)
                        Text(memory.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedMemoryID == memory.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search places")
            .navigationTitle("Link a Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
