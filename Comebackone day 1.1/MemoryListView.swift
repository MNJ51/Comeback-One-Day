//
//  MemoryListView.swift
//  Comebackone day 1.1
//

import SwiftUI

struct MemoryListView: View {
    @EnvironmentObject var store: MemoryStore
    @State private var selectedMemory: TravelMemory?

    private var sortedMemories: [TravelMemory] {
        store.memories.sorted {
            ($0.dateVisited ?? $0.dateAdded) > ($1.dateVisited ?? $1.dateAdded)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.memories.isEmpty {
                    ContentUnavailableView(
                        "No Places Yet",
                        systemImage: "mappin.slash",
                        description: Text("Add your first memory from the Map tab.")
                    )
                } else {
                    List {
                        ForEach(sortedMemories) { memory in
                            Button(action: {
                                selectedMemory = memory
                            }) {
                                MemoryRow(memory: memory)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("My Places")
            .sheet(item: $selectedMemory) { memory in
                MemoryDetailView(memoryID: memory.id)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let sorted = sortedMemories
        for index in offsets {
            store.delete(sorted[index])
        }
    }
}

struct MemoryRow: View {
    let memory: TravelMemory

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnail = PhotoStore.thumbnail(for: memory.coverPhotoFilename, maxDimension: 50) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: memory.category.icon)
                    .font(.title3)
                    .foregroundStyle(memory.category.color)
                    .frame(width: 50, height: 50)
                    .background(memory.category.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(memory.name)
                    .font(.headline)

                HStack(spacing: 6) {
                    Text(memory.category.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(memory.category.color.opacity(0.15))
                        .foregroundStyle(memory.category.color)
                        .clipShape(Capsule())

                    if let dateVisited = memory.dateVisited {
                        Text(dateVisited, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}
