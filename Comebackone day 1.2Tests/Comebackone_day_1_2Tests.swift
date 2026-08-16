//
//  Comebackone_day_1_2Tests.swift
//  Comebackone day 1.2Tests
//
//  Created by Michael Jee on 5/1/2026.
//

import Foundation
import Testing
@testable import Comebackone_day_1_2

@MainActor
struct TravelMemoryCodingTests {

    @Test func decodesLegacySinglePhotoFilename() throws {
        let json = """
        [{
            "id": "08D8A3C4-A65B-4119-876A-C7789A460D4F",
            "name": "Old Place",
            "latitude": -27.5,
            "longitude": 153.0,
            "category": "Restaurant",
            "photoFilename": "abc.jpg",
            "dateAdded": 700000000.0
        }]
        """
        let memories = try JSONDecoder().decode([TravelMemory].self, from: Data(json.utf8))
        #expect(memories.count == 1)
        #expect(memories[0].photoFilenames == ["abc.jpg"])
        #expect(memories[0].coverPhotoFilename == "abc.jpg")
        #expect(memories[0].rating == 0)
        #expect(memories[0].notes.isEmpty)
    }

    @Test func unknownCategoryFallsBackToLocation() throws {
        let json = """
        [{
            "id": "08D8A3C4-A65B-4119-876A-C7789A460D4F",
            "name": "Mystery",
            "latitude": 0,
            "longitude": 0,
            "category": "Spaceport",
            "dateAdded": 700000000.0
        }]
        """
        let memories = try JSONDecoder().decode([TravelMemory].self, from: Data(json.utf8))
        #expect(memories[0].category == .location)
    }

    @Test func roundTripPreservesAllFields() throws {
        let original = TravelMemory(
            name: "Story Bridge Hotel",
            latitude: -27.4633,
            longitude: 153.0515,
            category: .restaurant,
            photoFilenames: ["a.jpg", "b.jpg"],
            address: "200 Main St, Kangaroo Point QLD",
            rating: 4,
            notes: "Great pub food, sit outside.",
            dateVisited: Date(timeIntervalSinceReferenceDate: 700000000)
        )
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([TravelMemory].self, from: data)
        #expect(decoded == [original])
    }

    @Test func missingPhotoFieldsDecodeToEmptyList() throws {
        let json = """
        [{
            "id": "08D8A3C4-A65B-4119-876A-C7789A460D4F",
            "name": "No Photos",
            "latitude": 1,
            "longitude": 2,
            "category": "Hotel",
            "dateAdded": 700000000.0
        }]
        """
        let memories = try JSONDecoder().decode([TravelMemory].self, from: Data(json.utf8))
        #expect(memories[0].photoFilenames.isEmpty)
        #expect(memories[0].coverPhotoFilename == nil)
    }

    @Test func missingIsReceivedFromShareDefaultsToFalse() throws {
        let json = """
        [{
            "id": "08D8A3C4-A65B-4119-876A-C7789A460D4F",
            "name": "Old Place",
            "latitude": -27.5,
            "longitude": 153.0,
            "category": "Restaurant",
            "dateAdded": 700000000.0
        }]
        """
        let memories = try JSONDecoder().decode([TravelMemory].self, from: Data(json.utf8))
        #expect(memories[0].isReceivedFromShare == false)
    }

    @Test func sharedDeepLinkImportIsMarkedReceivedFromShare() throws {
        let original = TravelMemory(
            name: "Omilos",
            latitude: -27.4705,
            longitude: 153.0260,
            category: .restaurant,
            rating: 5
        )
        let url = try #require(original.shareURL)
        let imported = try #require(TravelMemory(shareURL: url))
        #expect(imported.isReceivedFromShare == true)

        let data = try JSONEncoder().encode([imported])
        let decoded = try JSONDecoder().decode([TravelMemory].self, from: data)
        #expect(decoded[0].isReceivedFromShare == true)
    }

    @Test func sharedDeepLinkCarriesSenderName() throws {
        let url = try #require(URL(string: "comebackoneday://add?name=Omilos&lat=-27.4705&lon=153.0260&cat=Restaurant&rating=5&from=Mike%27s%20iPhone"))
        let imported = try #require(TravelMemory(shareURL: url))
        #expect(imported.senderName == "Mike's iPhone")

        let data = try JSONEncoder().encode([imported])
        let decoded = try JSONDecoder().decode([TravelMemory].self, from: data)
        #expect(decoded[0].senderName == "Mike's iPhone")
    }

    @Test func missingSenderNameDecodesToNil() throws {
        let json = """
        [{
            "id": "08D8A3C4-A65B-4119-876A-C7789A460D4F",
            "name": "Old Place",
            "latitude": -27.5,
            "longitude": 153.0,
            "category": "Restaurant",
            "dateAdded": 700000000.0
        }]
        """
        let memories = try JSONDecoder().decode([TravelMemory].self, from: Data(json.utf8))
        #expect(memories[0].senderName == nil)
    }
}
