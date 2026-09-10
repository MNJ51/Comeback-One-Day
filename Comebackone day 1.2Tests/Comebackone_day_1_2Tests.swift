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

    @Test func cafeVibeSearchesOnlyCafeCategories() {
        let categories = ItineraryVibe.cafe.mapKitCategories
        #expect(categories.contains(.cafe))
        #expect(!categories.contains(.park))
        #expect(!categories.contains(.spa))
        #expect(!categories.contains(.nightlife))
        #expect(!categories.contains(.restaurant))
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
        let result = await ItineraryPlanner.discover(vibe: .relaxed, origin: origin, maxDistanceKm: 3, stopCount: 0)
        #expect(result.stops.isEmpty)
    }

    // MapKit exposes no rating, so "top" places are ranked by a free proxy:
    // having both a website and phone number (a verifiable, established
    // business), and — within the same tier — whichever is closer.
    @Test func rankPrefersPlacesWithWebsiteAndPhoneOverBarePins() {
        let origin = CLLocationCoordinate2D(latitude: -26.41, longitude: 153.09)
        let barePin = DiscoveredPlace(name: "Bare Pin", category: .location, coordinate: origin, address: nil, phoneNumber: nil, website: nil)
        let established = DiscoveredPlace(name: "Established Cafe", category: .cafe, coordinate: origin, address: nil, phoneNumber: "0712345678", website: "https://example.com")
        let ranked = PointOfInterestSearch.rank([barePin, established], from: origin)
        #expect(ranked.first?.name == "Established Cafe")
    }

    @Test func rankPrefersCloserPlaceWithinTheSameEstablishmentScore() {
        let origin = CLLocationCoordinate2D(latitude: -26.41, longitude: 153.09)
        let near = CLLocationCoordinate2D(latitude: -26.411, longitude: 153.09)
        let far = CLLocationCoordinate2D(latitude: -26.50, longitude: 153.09)
        let nearPlace = DiscoveredPlace(name: "Near", category: .location, coordinate: near, address: nil, phoneNumber: nil, website: nil)
        let farPlace = DiscoveredPlace(name: "Far", category: .location, coordinate: far, address: nil, phoneNumber: nil, website: nil)
        let ranked = PointOfInterestSearch.rank([farPlace, nearPlace], from: origin)
        #expect(ranked.map(\.name) == ["Near", "Far"])
    }

    @Test func orderByProximityFollowsAWalkableSequenceInsteadOfBacktracking() {
        // Deliberately shuffled so origin-distance order (what `rank` would
        // produce) is Far, Near, Mid — a walking route that visited them in
        // that order would backtrack past Near to reach Mid. Nearest-neighbor
        // sequencing should instead flow Near, Mid, Far, straight down the line.
        let origin = CLLocationCoordinate2D(latitude: -26.40, longitude: 153.09)
        let near = CLLocationCoordinate2D(latitude: -26.41, longitude: 153.09)
        let mid = CLLocationCoordinate2D(latitude: -26.42, longitude: 153.09)
        let far = CLLocationCoordinate2D(latitude: -26.43, longitude: 153.09)
        let nearPlace = DiscoveredPlace(name: "Near", category: .location, coordinate: near, address: nil, phoneNumber: nil, website: nil)
        let midPlace = DiscoveredPlace(name: "Mid", category: .location, coordinate: mid, address: nil, phoneNumber: nil, website: nil)
        let farPlace = DiscoveredPlace(name: "Far", category: .location, coordinate: far, address: nil, phoneNumber: nil, website: nil)
        let ordered = ItineraryPlanner.orderByProximity([farPlace, nearPlace, midPlace], from: origin)
        #expect(ordered.map(\.name) == ["Near", "Mid", "Far"])
    }

    @Test func selectDiverseDoesNotLetOneAbundantCategoryCrowdOutTheRest() {
        // Modeled on a real Sunshine Beach Foodie search: dozens of
        // restaurants, a handful of cafes, a couple of bakeries. A flat
        // prefix() after ranking (which sorts all-restaurants-first purely
        // because there are more close, verified ones) left only a single
        // cafe in a 9-stop itinerary. Round-robin selection should instead
        // spread picks across every category actually present.
        func place(_ name: String, _ category: Comebackone_day_1_2.Category, _ mapKitCategory: MKPointOfInterestCategory) -> DiscoveredPlace {
            DiscoveredPlace(name: name, category: category, coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), address: nil, phoneNumber: nil, website: nil, mapKitCategory: mapKitCategory)
        }
        let restaurants = (1...8).map { place("Restaurant \($0)", .restaurant, .restaurant) }
        let cafes = (1...2).map { place("Cafe \($0)", .cafe, .cafe) }
        let ranked = restaurants + cafes // restaurants sort first, as `rank` would produce

        let selected = ItineraryPlanner.selectDiverse(ranked, count: 6)
        let cafeCount = selected.filter { $0.mapKitCategory == .cafe }.count
        #expect(cafeCount == 2, "both cafes should make the cut instead of being crowded out by restaurants")
        #expect(selected.count == 6)
    }

    @Test func selectDiverseSpreadsAcrossFineGrainedCategoriesEvenWhenAppCategoryIsShared() {
        // Adventure-vibe categories (park, hiking, beach, kayaking...) all
        // map to the same coarse app-level `.location` category — bucketing
        // on that would make this round-robin a no-op. It must bucket on
        // MapKit's own finer category so a real adventure day mixes types
        // instead of defaulting to a run of generic parks.
        func place(_ name: String, _ mapKitCategory: MKPointOfInterestCategory) -> DiscoveredPlace {
            DiscoveredPlace(name: name, category: .location, coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), address: nil, phoneNumber: nil, website: nil, mapKitCategory: mapKitCategory)
        }
        let parks = (1...6).map { place("Park \($0)", .park) }
        let hikes = (1...2).map { place("Trail \($0)", .hiking) }
        let beaches = [place("Beach", .beach)]
        let ranked = parks + hikes + beaches // parks sort first, as `rank` would produce (same establishment score, arbitrary order)

        let selected = ItineraryPlanner.selectDiverse(ranked, count: 4)
        let categoriesPicked = Set(selected.compactMap(\.mapKitCategory))
        #expect(categoriesPicked.contains(.hiking), "hiking should make the cut instead of being crowded out by parks")
        #expect(categoriesPicked.contains(.beach), "the beach should make the cut instead of being crowded out by parks")
    }

    @Test func nameSuggestsUnrelatedProfessionalServiceCatchesMislabeledListings() {
        // Real MapKit listings seen this session, complete with phone and
        // website (which is why `rank` trusted them), but tagged with a
        // category that plainly doesn't match the business itself.
        #expect(PointOfInterestSearch.nameSuggestsUnrelatedProfessionalService("IntExt Design"))
        #expect(PointOfInterestSearch.nameSuggestsUnrelatedProfessionalService("Sunshine Progressive Kinesiology and Meditation") == false)

        // Real adventure/food places should never be caught by this.
        #expect(!PointOfInterestSearch.nameSuggestsUnrelatedProfessionalService("Tanglewood Walk"))
        #expect(!PointOfInterestSearch.nameSuggestsUnrelatedProfessionalService("National Park Information Centre"))
        #expect(!PointOfInterestSearch.nameSuggestsUnrelatedProfessionalService("Go Ride A Wave"))
        #expect(!PointOfInterestSearch.nameSuggestsUnrelatedProfessionalService("Season Restaurant"))
    }
}

struct CuisineTests {
    @Test func matchesObviousCuisineKeywordsInAName() {
        #expect(Cuisine.thai.matches(name: "Thai Orchid"))
        #expect(Cuisine.japanese.matches(name: "Sakura Sushi Bar"))
        #expect(Cuisine.italian.matches(name: "Bella Pizzeria"))
        #expect(Cuisine.vietnamese.matches(name: "Pho 88"))
    }

    @Test func doesNotMatchUnrelatedNames() {
        #expect(!Cuisine.thai.matches(name: "The Local Diner"))
        #expect(!Cuisine.japanese.matches(name: "Season Restaurant"))
    }

    /// A short cuisine keyword ("pho") must not false-match a totally
    /// unrelated word that merely contains it as a substring.
    @Test func shortKeywordsDoNotFalseMatchContainingWords() {
        #expect(!Cuisine.vietnamese.matches(name: "iPhone Repair"))
    }

    /// Broader dish/regional-name coverage added after a real restaurant
    /// ("Din Tai Fung") matched nothing under the old, thinner keyword
    /// lists — these are names that gain a match specifically because of
    /// that expansion, not names the old lists already caught.
    @Test func matchesBroaderDishAndRegionalKeywords() {
        #expect(Cuisine.chinese.matches(name: "Golden Wok"))
        #expect(Cuisine.japanese.matches(name: "Tokyo Ramen House"))
        #expect(Cuisine.indian.matches(name: "Mumbai Curry House"))
        #expect(Cuisine.italian.matches(name: "Napoli Pizza Co"))
        #expect(Cuisine.mexican.matches(name: "El Taco Loco"))
        #expect(Cuisine.american.matches(name: "Route 66 Diner"))
        #expect(Cuisine.mediterranean.matches(name: "Athens Greek Taverna"))
        #expect(Cuisine.korean.matches(name: "Seoul Kitchen"))
    }

    /// "Din Tai Fung" is the real case that prompted the keyword expansion —
    /// worth documenting explicitly that it still won't match anything,
    /// since its name has zero cuisine or dish signal in it at all. No
    /// amount of keyword-list broadening can fix this specific case; it's
    /// the hard limit of a name-only heuristic, not a bug to chase further.
    @Test func namesWithNoCuisineSignalStillMatchNothing() {
        #expect(!Cuisine.chinese.matches(name: "Din Tai Fung"))
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

    @Test func roundTripPreservesPhotosVideosJournalNameLocationAndWeather() throws {
        let entry = JournalEntry(
            text: "Rainy day at the coast.",
            photoFilenames: ["a.jpg", "b.jpg"],
            videoFilenames: ["c.mov"],
            journalName: "Travel",
            latitude: -26.41,
            longitude: 153.09,
            locationLabel: "Noosa, QLD",
            weatherTemperatureCelsius: 21.5,
            weatherSymbolName: "cloud.rain.fill",
            weatherDescription: "Rain"
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(JournalEntry.self, from: data)
        #expect(decoded == entry)
        #expect(decoded.coverPhotoFilename == "a.jpg")
        #expect(decoded.coordinate?.latitude == -26.41)
    }

    @Test func mediaAndContextFieldsDefaultToEmptyOrNil() {
        let entry = JournalEntry(text: "Nothing special.")
        #expect(entry.photoFilenames.isEmpty)
        #expect(entry.videoFilenames.isEmpty)
        #expect(entry.journalName == nil)
        #expect(entry.coordinate == nil)
        #expect(entry.coverPhotoFilename == nil)
    }

    @Test func roundTripPreservesAudioFilename() throws {
        let entry = JournalEntry(text: "Recorded a note about this spot.", audioFilename: "note.m4a")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(JournalEntry.self, from: data)
        #expect(decoded == entry)
        #expect(decoded.audioFilename == "note.m4a")
    }

    /// The actual backward-compatibility guarantee this design depends on:
    /// entries persisted before `audioFilename` existed have no such key in
    /// their JSON at all. Swift's synthesized decoder uses `decodeIfPresent`
    /// for Optional stored properties, so this must still decode cleanly.
    @Test func decodesOldEntryMissingAudioFilenameKey() throws {
        let json = """
        {
            "id": "08D8A3C4-A65B-4119-876A-C7789A460D4F",
            "date": 800000000,
            "text": "Written before audio existed.",
            "photoFilenames": [],
            "videoFilenames": [],
            "dateAdded": 800000000
        }
        """
        let decoded = try JSONDecoder().decode(JournalEntry.self, from: Data(json.utf8))
        #expect(decoded.audioFilename == nil)
        #expect(decoded.text == "Written before audio existed.")
    }

    @Test func roundTripPreservesMood() throws {
        let entry = JournalEntry(text: "Best day of the trip.", mood: .amazing)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(JournalEntry.self, from: data)
        #expect(decoded == entry)
        #expect(decoded.mood == .amazing)
    }

    /// Same backward-compatibility guarantee as `audioFilename`: entries
    /// persisted before mood tagging existed have no such key at all.
    @Test func decodesOldEntryMissingMoodKey() throws {
        let json = """
        {
            "id": "08D8A3C4-A65B-4119-876A-C7789A460D4F",
            "date": 800000000,
            "text": "Written before mood tagging existed.",
            "photoFilenames": [],
            "videoFilenames": [],
            "dateAdded": 800000000
        }
        """
        let decoded = try JSONDecoder().decode(JournalEntry.self, from: Data(json.utf8))
        #expect(decoded.mood == nil)
    }

    @Test func roundTripPreservesTitle() throws {
        let entry = JournalEntry(title: "A Great Day", text: "Explored the old town.")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(JournalEntry.self, from: data)
        #expect(decoded == entry)
        #expect(decoded.title == "A Great Day")
    }

    /// Same backward-compatibility guarantee as `audioFilename`/`mood`:
    /// entries persisted before titles existed have no such key at all.
    @Test func decodesOldEntryMissingTitleKey() throws {
        let json = """
        {
            "id": "08D8A3C4-A65B-4119-876A-C7789A460D4F",
            "date": 800000000,
            "text": "Written before titles existed.",
            "photoFilenames": [],
            "videoFilenames": [],
            "dateAdded": 800000000
        }
        """
        let decoded = try JSONDecoder().decode(JournalEntry.self, from: Data(json.utf8))
        #expect(decoded.title == nil)
    }

    @Test func roundTripPreservesDrawingFilename() throws {
        let entry = JournalEntry(text: "Sketched the view.", drawingFilename: "sketch.drawing")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(JournalEntry.self, from: data)
        #expect(decoded == entry)
        #expect(decoded.drawingFilename == "sketch.drawing")
    }

    /// Same backward-compatibility guarantee as `audioFilename`/`mood`:
    /// entries persisted before sketches existed have no such key at all.
    @Test func decodesOldEntryMissingDrawingFilenameKey() throws {
        let json = """
        {
            "id": "08D8A3C4-A65B-4119-876A-C7789A460D4F",
            "date": 800000000,
            "text": "Written before sketches existed.",
            "photoFilenames": [],
            "videoFilenames": [],
            "dateAdded": 800000000
        }
        """
        let decoded = try JSONDecoder().decode(JournalEntry.self, from: Data(json.utf8))
        #expect(decoded.drawingFilename == nil)
    }

    @Test func roundTripPreservesSourceAssetIdentifiers() throws {
        let entry = JournalEntry(text: "From a suggested moment.", sourceAssetIdentifiers: ["ABC/L0/001", "ABC/L0/002"])
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(JournalEntry.self, from: data)
        #expect(decoded == entry)
        #expect(decoded.sourceAssetIdentifiers == ["ABC/L0/001", "ABC/L0/002"])
    }

    /// Same backward-compatibility guarantee as `audioFilename`/`mood`/
    /// `drawingFilename`: entries persisted before moment suggestions existed
    /// have no such key at all.
    @Test func decodesOldEntryMissingSourceAssetIdentifiersKey() throws {
        let json = """
        {
            "id": "08D8A3C4-A65B-4119-876A-C7789A460D4F",
            "date": 800000000,
            "text": "Written before moment suggestions existed.",
            "photoFilenames": [],
            "videoFilenames": [],
            "dateAdded": 800000000
        }
        """
        let decoded = try JSONDecoder().decode(JournalEntry.self, from: Data(json.utf8))
        #expect(decoded.sourceAssetIdentifiers == nil)
    }
}

struct JournalStreakTests {
    private func date(daysAgo: Int, calendar: Calendar = .current, referenceDate: Date) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: referenceDate)!
    }

    @Test func emptyEntriesHaveNoStreak() {
        #expect(JournalStreak.currentStreak(entryDates: []) == 0)
    }

    @Test func consecutiveDaysEndingTodayCountCorrectly() {
        let today = Date()
        let dates = [0, 1, 2].map { date(daysAgo: $0, referenceDate: today) }
        #expect(JournalStreak.currentStreak(entryDates: dates, asOf: today) == 3)
    }

    @Test func missingTodayStillCountsFromYesterdayWithGrace() {
        // Wrote every day up to yesterday, nothing yet today — the streak
        // shouldn't visually break until today actually ends.
        let today = Date()
        let dates = [1, 2, 3].map { date(daysAgo: $0, referenceDate: today) }
        #expect(JournalStreak.currentStreak(entryDates: dates, asOf: today) == 3)
    }

    @Test func gapBreaksTheStreak() {
        let today = Date()
        // Today and yesterday written, then a gap, then older entries —
        // the streak should only count the unbroken run back from today.
        let dates = [0, 1, 3, 4].map { date(daysAgo: $0, referenceDate: today) }
        #expect(JournalStreak.currentStreak(entryDates: dates, asOf: today) == 2)
    }

    @Test func longestStreakOfEmptyEntriesIsZero() {
        #expect(JournalStreak.longestStreak(entryDates: []) == 0)
    }

    @Test func longestStreakFindsASingleLongRun() {
        let today = Date()
        let dates = (0...4).map { date(daysAgo: $0, referenceDate: today) }
        #expect(JournalStreak.longestStreak(entryDates: dates) == 5)
    }

    @Test func longestStreakPicksTheLongestRunNotTheMostRecent() {
        let today = Date()
        // A 2-day run ending yesterday/today, and an older 4-day run further
        // back — the longest streak should report the older, longer run.
        let recentRun = [0, 1].map { date(daysAgo: $0, referenceDate: today) }
        let olderRun = (10...13).map { date(daysAgo: $0, referenceDate: today) }
        #expect(JournalStreak.longestStreak(entryDates: recentRun + olderRun) == 4)
    }

    @Test func emptyEntriesHaveNoWeeklyStreak() {
        #expect(JournalStreak.currentWeeklyStreak(entryDates: []) == 0)
    }

    @Test func consecutiveWeeksEndingThisWeekCountCorrectly() {
        let today = Date()
        // One entry each in this week, last week, and the week before.
        let dates = [0, 7, 14].map { date(daysAgo: $0, referenceDate: today) }
        #expect(JournalStreak.currentWeeklyStreak(entryDates: dates, asOf: today) == 3)
    }

    @Test func missingThisWeekStillCountsFromLastWeekWithGrace() {
        let today = Date()
        // Nothing written yet this week, but last week and the week before
        // were both written — shouldn't visually break until this week ends.
        let dates = [7, 14].map { date(daysAgo: $0, referenceDate: today) }
        #expect(JournalStreak.currentWeeklyStreak(entryDates: dates, asOf: today) == 2)
    }

    @Test func weekGapBreaksTheWeeklyStreak() {
        let today = Date()
        // This week and last week written, then a skipped week, then an
        // older entry — only the unbroken run back from this week counts.
        let dates = [0, 7, 21].map { date(daysAgo: $0, referenceDate: today) }
        #expect(JournalStreak.currentWeeklyStreak(entryDates: dates, asOf: today) == 2)
    }

    @Test func longestWeeklyStreakOfEmptyEntriesIsZero() {
        #expect(JournalStreak.longestWeeklyStreak(entryDates: []) == 0)
    }

    @Test func longestWeeklyStreakPicksTheLongestRunNotTheMostRecent() {
        let today = Date()
        // A 2-week run ending this week, and an older 4-week run further
        // back — the longest streak should report the older, longer run.
        let recentRun = [0, 7].map { date(daysAgo: $0, referenceDate: today) }
        let olderRun = [70, 77, 84, 91].map { date(daysAgo: $0, referenceDate: today) }
        #expect(JournalStreak.longestWeeklyStreak(entryDates: recentRun + olderRun) == 4)
    }
}

struct JournalExporterTests {
    @Test func markdownIncludesTitleMoodAndText() {
        let entry = JournalEntry(
            date: Date(timeIntervalSince1970: 800000000),
            title: "A Great Day",
            text: "Explored the old town.",
            mood: .amazing
        )
        let markdown = JournalExporter.markdown(for: [entry])
        #expect(markdown.contains("A Great Day"))
        #expect(markdown.contains("Explored the old town."))
        #expect(markdown.contains(entry.mood!.emoji))
        #expect(markdown.contains(entry.mood!.label))
    }

    @Test func markdownFallsBackToDateWhenNoTitle() {
        let entry = JournalEntry(date: Date(timeIntervalSince1970: 800000000), text: "No title today.")
        let markdown = JournalExporter.markdown(for: [entry])
        #expect(markdown.contains("No title today."))
        #expect(!markdown.isEmpty)
    }

    @Test func markdownOrdersEntriesNewestFirst() {
        let older = JournalEntry(date: Date(timeIntervalSince1970: 700000000), text: "Older entry.")
        let newer = JournalEntry(date: Date(timeIntervalSince1970: 900000000), text: "Newer entry.")
        let markdown = JournalExporter.markdown(for: [older, newer])
        let newerRange = markdown.range(of: "Newer entry.")
        let olderRange = markdown.range(of: "Older entry.")
        #expect(newerRange != nil && olderRange != nil)
        #expect(newerRange!.lowerBound < olderRange!.lowerBound)
    }

    @Test func markdownOfEmptyEntriesIsEmpty() {
        #expect(JournalExporter.markdown(for: []).isEmpty)
    }
}

struct EventCodingTests {
    @Test func roundTripPreservesAllFields() throws {
        let event = Event(
            name: "Radiohead",
            date: Date(timeIntervalSince1970: 900000000),
            latitude: -27.4705,
            longitude: 153.0260,
            address: "Riverstage, Brisbane",
            website: "https://radiohead.com",
            photoFilenames: ["a.jpg"],
            attended: true
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(Event.self, from: data)
        #expect(decoded == event)
    }

    @Test func attendedDefaultsToFalse() {
        let event = Event(name: "Splendour in the Grass", date: Date(), latitude: -28.68, longitude: 153.6)
        #expect(event.attended == false)
    }

    @Test func photoFilenamesDefaultsToEmpty() {
        let event = Event(name: "A Concert", date: Date(), latitude: 0, longitude: 0)
        #expect(event.photoFilenames.isEmpty)
        #expect(event.coverPhotoFilename == nil)
    }

    /// Synthesized Codable uses `decodeIfPresent` for Optional stored
    /// properties, so an old-shape JSON missing a key that was added later
    /// (address/website here) still decodes cleanly rather than failing.
    @Test func decodesJSONMissingOptionalKeys() throws {
        let json = """
        {
            "id": "08D8A3C4-A65B-4119-876A-C7789A460D4F",
            "name": "Coachella",
            "date": 900000000,
            "latitude": 33.6803,
            "longitude": -116.2378,
            "photoFilenames": [],
            "attended": false,
            "dateAdded": 900000000
        }
        """
        let decoded = try JSONDecoder().decode(Event.self, from: Data(json.utf8))
        #expect(decoded.address == nil)
        #expect(decoded.website == nil)
        #expect(decoded.name == "Coachella")
    }

    @Test func websiteURLAddsSchemeWhenMissing() {
        let event = Event(name: "A Concert", date: Date(), latitude: 0, longitude: 0, website: "example.com")
        #expect(event.websiteURL?.absoluteString == "https://example.com")
    }
}

struct EventSortingTests {
    private static func event(_ name: String, daysFromNow: Int, attended: Bool = false) -> Event {
        let date = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date())!
        return Event(name: name, date: date, latitude: 0, longitude: 0, attended: attended)
    }

    @Test func upcomingEventsSortAscendingBySoonestFirst() {
        let events = [Self.event("Later", daysFromNow: 10), Self.event("Soonest", daysFromNow: 1), Self.event("Middle", daysFromNow: 5)]
        let upcoming = events.filter { !$0.attended }.sorted { $0.date < $1.date }
        #expect(upcoming.map(\.name) == ["Soonest", "Middle", "Later"])
    }

    @Test func attendedEventsSortDescendingByMostRecentFirst() {
        let events = [
            Self.event("Oldest", daysFromNow: -30, attended: true),
            Self.event("Most Recent", daysFromNow: -1, attended: true),
            Self.event("Middle", daysFromNow: -10, attended: true)
        ]
        let attended = events.filter(\.attended).sorted { $0.date > $1.date }
        #expect(attended.map(\.name) == ["Most Recent", "Middle", "Oldest"])
    }

    @Test func attendedAndUpcomingEventsSplitIntoCorrectSections() {
        let events = [
            Self.event("Future Show", daysFromNow: 5),
            Self.event("Past Show", daysFromNow: -5, attended: true),
            Self.event("Another Future Show", daysFromNow: 2)
        ]
        let upcoming = events.filter { !$0.attended }
        let attended = events.filter(\.attended)
        #expect(upcoming.map(\.name).sorted() == ["Another Future Show", "Future Show"])
        #expect(attended.map(\.name) == ["Past Show"])
    }
}
