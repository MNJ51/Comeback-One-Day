//
//  JournalModels.swift
//  Comebackone day 1.2
//

import Foundation

/// A free-form journal entry for a given day, optionally linked to one of the
/// user's saved places. Brand new type (no legacy on-disk shape to support),
/// so synthesized Codable is fine — unlike TravelMemory, which hand-writes
/// its Codable conformance for backward compatibility.
struct JournalEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var text: String
    /// The saved place (TravelMemory.id) this entry is about, if any.
    var linkedMemoryID: UUID?
    let dateAdded: Date

    init(id: UUID = UUID(), date: Date = Date(), text: String, linkedMemoryID: UUID? = nil, dateAdded: Date = Date()) {
        self.id = id
        self.date = date
        self.text = text
        self.linkedMemoryID = linkedMemoryID
        self.dateAdded = dateAdded
    }
}
