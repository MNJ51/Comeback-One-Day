//
//  Comebackone_day_1_2Tests.swift
//  Comebackone day 1.2Tests
//
//  Created by Michael Jee on 5/1/2026.
//

import CoreLocation
import Foundation
import MapKit
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

    @Test func missingVideoFilenamesDecodesToEmptyList() throws {
        let json = """
        [{
            "id": "08D8A3C4-A65B-4119-876A-C7789A460D4F",
            "name": "No Videos",
            "latitude": 1,
            "longitude": 2,
            "category": "Hotel",
            "dateAdded": 700000000.0
        }]
        """
        let memories = try JSONDecoder().decode([TravelMemory].self, from: Data(json.utf8))
        #expect(memories[0].videoFilenames.isEmpty)
    }

    @Test func videoFilenamesRoundTrip() throws {
        let memory = TravelMemory(name: "Clip Test", latitude: 1, longitude: 2, category: .location, videoFilenames: ["a.mov", "b.mov"])
        let data = try JSONEncoder().encode(memory)
        let decoded = try JSONDecoder().decode(TravelMemory.self, from: data)
        #expect(decoded.videoFilenames == ["a.mov", "b.mov"])
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

    @Test func countryReadsLastAddressComponent() throws {
        let memory = TravelMemory(
            name: "Omilos",
            latitude: -27.4705,
            longitude: 153.0260,
            category: .restaurant,
            address: "94 Poath Rd, Hughesdale, VIC, 3166, Australia"
        )
        #expect(memory.country == "Australia")
    }

    @Test func countryIsNilWithoutAnAddress() throws {
        let memory = TravelMemory(
            name: "No Address",
            latitude: 0,
            longitude: 0,
            category: .location
        )
        #expect(memory.country == nil)
    }

    @Test func missingPhoneNumberDecodesToNil() throws {
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
        #expect(memories[0].phoneNumber == nil)
    }

    @Test func phoneCallURLStripsFormattingButKeepsPlus() throws {
        let memory = TravelMemory(
            name: "Omilos",
            latitude: -27.4705,
            longitude: 153.0260,
            category: .restaurant,
            phoneNumber: "+1 (555) 123-4567"
        )
        #expect(memory.phoneCallURL?.absoluteString == "tel:+15551234567")
    }

    @Test func phoneCallURLIsNilWithoutAPhoneNumber() throws {
        let memory = TravelMemory(
            name: "No Phone",
            latitude: 0,
            longitude: 0,
            category: .location
        )
        #expect(memory.phoneCallURL == nil)
    }

    @Test func shareURLIsAUniversalLinkOnTheLandingPageDomain() throws {
        let memory = TravelMemory(
            name: "Omilos",
            latitude: -27.4705,
            longitude: 153.0260,
            category: .restaurant
        )
        let url = try #require(memory.shareURL)
        #expect(url.scheme == "https")
        #expect(url.host == "www.thehealthclubonline.com")
        #expect(url.path == "/comebackonedayapp/add")
    }

    @Test func universalLinkImportIsMarkedReceivedFromShare() throws {
        let url = try #require(URL(string: "https://www.thehealthclubonline.com/comebackonedayapp/add?name=Omilos&lat=-27.4705&lon=153.0260&cat=Restaurant&rating=5"))
        let imported = try #require(TravelMemory(shareURL: url))
        #expect(imported.name == "Omilos")
        #expect(imported.isReceivedFromShare == true)
    }

    @Test func universalLinkImportWorksWithoutWWW() throws {
        let url = try #require(URL(string: "https://thehealthclubonline.com/comebackonedayapp/add?name=Omilos&lat=-27.4705&lon=153.0260&cat=Restaurant&rating=5"))
        let imported = try #require(TravelMemory(shareURL: url))
        #expect(imported.name == "Omilos")
    }

    @Test func legacySchemeLinksStillImportAfterSwitchingToUniversalLinks() throws {
        let url = try #require(URL(string: "comebackoneday://add?name=Omilos&lat=-27.4705&lon=153.0260&cat=Restaurant&rating=5"))
        let imported = try #require(TravelMemory(shareURL: url))
        #expect(imported.name == "Omilos")
    }

    @Test func unrelatedHTTPSLinksAreNotImported() throws {
        let url = try #require(URL(string: "https://www.thehealthclubonline.com/some-other-page"))
        #expect(TravelMemory(shareURL: url) == nil)
    }

    @Test func missingTripNameDecodesToNil() throws {
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
        #expect(memories[0].tripName == nil)
    }

    @Test func missingVoiceNoteFilenameDecodesToNil() throws {
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
        #expect(memories[0].voiceNoteFilename == nil)
    }

    @Test func tripNameAndVoiceNoteFilenameRoundTrip() throws {
        let original = TravelMemory(
            name: "Omilos",
            latitude: -27.4705,
            longitude: 153.0260,
            category: .restaurant,
            tripName: "Greece 2026",
            voiceNoteFilename: "abc123.m4a"
        )
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([TravelMemory].self, from: data)
        #expect(decoded[0].tripName == "Greece 2026")
        #expect(decoded[0].voiceNoteFilename == "abc123.m4a")
        #expect(decoded == [original])
    }

    @Test func missingVisitStatusDecodesToBeenThere() throws {
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
        #expect(memories[0].visitStatus == .beenThere)
    }

    @Test func visitStatusRoundTrips() throws {
        let original = TravelMemory(
            name: "Someday Cafe",
            latitude: -27.4705,
            longitude: 153.0260,
            category: .cafe,
            visitStatus: .wantToGo
        )
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([TravelMemory].self, from: data)
        #expect(decoded[0].visitStatus == .wantToGo)
        #expect(decoded == [original])
    }

    @Test func missingIsGlutenFreeDecodesToFalse() throws {
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
        #expect(memories[0].isGlutenFree == false)
    }

    @Test func isGlutenFreeRoundTrips() throws {
        let original = TravelMemory(
            name: "Celiac-Friendly Bistro",
            latitude: -27.4705,
            longitude: 153.0260,
            category: .restaurant,
            isGlutenFree: true
        )
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([TravelMemory].self, from: data)
        #expect(decoded[0].isGlutenFree == true)
        #expect(decoded == [original])
    }

    @Test func isOnThisDayMatchesSameMonthDayEarlierYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 12))!
        let lastYear = calendar.date(from: DateComponents(year: 2025, month: 8, day: 20, hour: 9))!

        let memory = TravelMemory(
            name: "Omilos",
            latitude: -27.4705,
            longitude: 153.0260,
            category: .restaurant,
            dateVisited: lastYear
        )
        #expect(memory.isOnThisDay(relativeTo: now, calendar: calendar) == true)
        #expect(memory.yearsAgo(relativeTo: now, calendar: calendar) == 1)
    }

    @Test func isOnThisDayIsFalseForDifferentDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let differentDay = calendar.date(from: DateComponents(year: 2025, month: 8, day: 21))!

        let memory = TravelMemory(
            name: "Omilos",
            latitude: -27.4705,
            longitude: 153.0260,
            category: .restaurant,
            dateVisited: differentDay
        )
        #expect(memory.isOnThisDay(relativeTo: now, calendar: calendar) == false)
    }

    @Test func isOnThisDayIsFalseForSameYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 18))!
        let earlierToday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 9))!

        let memory = TravelMemory(
            name: "Omilos",
            latitude: -27.4705,
            longitude: 153.0260,
            category: .restaurant,
            dateVisited: earlierToday
        )
        #expect(memory.isOnThisDay(relativeTo: now, calendar: calendar) == false)
    }

    @Test func isOnThisDayFallsBackToDateAddedWithoutDateVisited() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let twoYearsAgo = calendar.date(from: DateComponents(year: 2024, month: 8, day: 20))!

        let memory = TravelMemory(
            name: "Omilos",
            latitude: -27.4705,
            longitude: 153.0260,
            category: .restaurant,
            dateAdded: twoYearsAgo,
            dateVisited: nil
        )
        #expect(memory.isOnThisDay(relativeTo: now, calendar: calendar) == true)
        #expect(memory.yearsAgo(relativeTo: now, calendar: calendar) == 2)
    }

    @Test func sharedDeepLinkCarriesPhoneNumber() throws {
        let original = TravelMemory(
            name: "Omilos",
            latitude: -27.4705,
            longitude: 153.0260,
            category: .restaurant,
            phoneNumber: "+61 7 1234 5678"
        )
        let url = try #require(original.shareURL)
        let imported = try #require(TravelMemory(shareURL: url))
        #expect(imported.phoneNumber == "+61 7 1234 5678")
    }
}

struct ItineraryPlannerTests {
    // discover() itself makes a live MapKit network call, so — consistent with
    // this codebase's other MapKit-backed code (LocationSearchService is not
    // unit tested either) — only the pure, deterministic logic around it is
    // tested here: category mapping and each vibe's search category set.

    @Test func categoryMappingCoversCommonMapKitCategories() {
        #expect(Comebackone_day_1_2.Category.from(mapKitCategory: .restaurant) == .restaurant)
        #expect(Comebackone_day_1_2.Category.from(mapKitCategory: .cafe) == .cafe)
        #expect(Comebackone_day_1_2.Category.from(mapKitCategory: .bakery) == .cafe)
        #expect(Comebackone_day_1_2.Category.from(mapKitCategory: .hotel) == .hotel)
        #expect(Comebackone_day_1_2.Category.from(mapKitCategory: .foodMarket) == .foodMarket)
        #expect(Comebackone_day_1_2.Category.from(mapKitCategory: .brewery) == .bar)
        #expect(Comebackone_day_1_2.Category.from(mapKitCategory: .winery) == .bar)
    }

    @Test func categoryMappingFallsBackToLocationForUnmappedCategories() {
        #expect(Comebackone_day_1_2.Category.from(mapKitCategory: .museum) == .location)
        #expect(Comebackone_day_1_2.Category.from(mapKitCategory: nil) == .location)
    }

    @Test func foodieSearchesFoodCategories() {
        let categories = ItineraryVibe.foodie.mapKitCategories
        #expect(categories.contains(.restaurant))
        #expect(categories.contains(.cafe))
        #expect(categories.contains(.foodMarket))
    }

    @Test func adventureSearchesOutdoorCategories() {
        let categories = ItineraryVibe.adventure.mapKitCategories
        #expect(categories.contains(.park))
        #expect(categories.contains(.hiking))
        #expect(!categories.contains(.restaurant))
    }

    @Test func cultureSearchesCulturalCategories() {
        let categories = ItineraryVibe.culture.mapKitCategories
        #expect(categories.contains(.museum))
        #expect(categories.contains(.landmark))
    }

    @Test func mysteryVibeUsesTheOffbeatPool() {
        #expect(ItineraryVibe.mystery.mapKitCategories == ItineraryPlanner.mysteryCategoryPool)
        // The offbeat pool shouldn't just be a rehash of the other vibes' obvious picks.
        #expect(!ItineraryPlanner.mysteryCategoryPool.contains(.restaurant))
        #expect(!ItineraryPlanner.mysteryCategoryPool.contains(.museum))
    }

    @Test func everyVibeHasAtLeastOneSearchCategory() {
        for vibe in ItineraryVibe.allCases {
            #expect(!vibe.mapKitCategories.isEmpty)
        }
    }

    @Test func discoverReturnsEmptyForNonPositiveStopCount() async {
        let origin = CLLocationCoordinate2D(latitude: -27.4705, longitude: 153.0260)
        let stops = await ItineraryPlanner.discover(vibe: .relaxed, origin: origin, maxDistanceKm: 3, stopCount: 0)
        #expect(stops.isEmpty)
    }

    // MapKit exposes no rating, so "top" places are ranked by a free proxy:
    // having both a website and phone number (a verifiable, established
    // business), falling back to MapKit's own relevance order as a tiebreak.
    @Test func rankPrefersPlacesWithWebsiteAndPhoneOverBarePins() {
        let coordinate = CLLocationCoordinate2D(latitude: -26.41, longitude: 153.09)
        let barePin = DiscoveredPlace(name: "Bare Pin", category: .location, coordinate: coordinate, address: nil, phoneNumber: nil, website: nil)
        let established = DiscoveredPlace(name: "Established Cafe", category: .cafe, coordinate: coordinate, address: nil, phoneNumber: "0712345678", website: "https://example.com")
        let ranked = ItineraryPlanner.rank([barePin, established])
        #expect(ranked.first?.name == "Established Cafe")
    }

    @Test func rankPreservesOriginalOrderWithinTheSameEstablishmentScore() {
        let coordinate = CLLocationCoordinate2D(latitude: -26.41, longitude: 153.09)
        let first = DiscoveredPlace(name: "First", category: .location, coordinate: coordinate, address: nil, phoneNumber: nil, website: nil)
        let second = DiscoveredPlace(name: "Second", category: .location, coordinate: coordinate, address: nil, phoneNumber: nil, website: nil)
        let ranked = ItineraryPlanner.rank([first, second])
        #expect(ranked.map(\.name) == ["First", "Second"])
    }
}

struct JournalEntryCodingTests {
    @Test func roundTripPreservesAllFields() throws {
        let entry = JournalEntry(date: Date(timeIntervalSince1970: 800000000), text: "Great day exploring the old town.", linkedMemoryID: UUID())
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(JournalEntry.self, from: data)
        #expect(decoded == entry)
    }

    @Test func linkedMemoryIDDefaultsToNil() {
        let entry = JournalEntry(text: "No place linked today.")
        #expect(entry.linkedMemoryID == nil)
    }

    @Test func roundTripWithoutLinkedMemoryPreservesNil() throws {
        let entry = JournalEntry(text: "Just a quiet day.")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(JournalEntry.self, from: data)
        #expect(decoded.linkedMemoryID == nil)
    }
}
