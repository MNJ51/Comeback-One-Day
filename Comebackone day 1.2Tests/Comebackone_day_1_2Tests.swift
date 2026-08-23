//
//  Comebackone_day_1_2Tests.swift
//  Comebackone day 1.2Tests
//
//  Created by Michael Jee on 5/1/2026.
//

import CoreLocation
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

/// A minimal linear congruential generator so mystery-stop selection is
/// reproducible in tests instead of depending on SystemRandomNumberGenerator.
private struct DeterministicRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

struct ItineraryPlannerTests {
    let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)

    private func place(_ name: String, lon: Double, category: Comebackone_day_1_2.Category = .cafe, rating: Int = 3, status: VisitStatus = .beenThere, isGlutenFree: Bool = false) -> TravelMemory {
        TravelMemory(name: name, latitude: 0, longitude: lon, category: category, rating: rating, visitStatus: status, isGlutenFree: isGlutenFree)
    }

    @Test func generateReturnsEmptyForNoMemories() {
        let stops = ItineraryPlanner.generate(from: [], vibe: .relaxed, origin: origin)
        #expect(stops.isEmpty)
    }

    @Test func generateOrdersStopsNearestFirstFromOrigin() {
        let near = place("Near", lon: 0.005)
        let mid = place("Mid", lon: 0.01)
        let far = place("Far", lon: 0.02)
        let stops = ItineraryPlanner.generate(from: [mid, far, near], vibe: .relaxed, origin: origin, stopCount: 3)

        let names = stops.filter { !$0.isMysteryStop }.map { $0.memory.name }
        #expect(names == ["Near", "Mid", "Far"])
    }

    @Test func generatePicksBestScoringPlacesOverStopCount() {
        let good1 = place("Good1", lon: 0.005)
        let good2 = place("Good2", lon: 0.006)
        let good3 = place("Good3", lon: 0.007)
        // Far away and a poor fit for .relaxed (cafe/bar/hotel score higher) — should lose out.
        let distractor = place("Distractor", lon: 1.0, category: .location, rating: 1)

        let stops = ItineraryPlanner.generate(from: [good1, good2, good3, distractor], vibe: .relaxed, origin: origin, stopCount: 3)
        let names = Set(stops.filter { !$0.isMysteryStop }.map { $0.memory.name })
        #expect(names == ["Good1", "Good2", "Good3"])
    }

    @Test func mysteryPoolOnlyContainsWishlistPlacesNotOnTheRoute() {
        let route = [place("OnRoute", lon: 0.01, status: .wantToGo)]
        let wishlistOffRoute = place("Wishlist", lon: 0.02, status: .wantToGo)
        let beenThereOffRoute = place("BeenThere", lon: 0.03, status: .beenThere)

        let pool = ItineraryPlanner.mysteryPool(
            excluding: route,
            in: [route[0], wishlistOffRoute, beenThereOffRoute],
            vibe: .relaxed,
            origin: origin
        )
        #expect(pool.map(\.name) == ["Wishlist"])
    }

    @Test func mysteryPoolExcludesTheTopScoringHalf() {
        // 4 wishlist candidates, all off-route: the closest two are the "obvious"
        // picks and should be excluded, leaving only the two farther ones.
        let places = (0..<4).map { i in
            place("Wishlist\(i)", lon: Double(i + 1) * 0.01, status: .wantToGo)
        }
        let pool = ItineraryPlanner.mysteryPool(excluding: [], in: places, vibe: .relaxed, origin: origin)
        #expect(pool.map(\.name) == ["Wishlist2", "Wishlist3"])
    }

    @Test func generateAddsMysteryStopFromWishlistOnly() throws {
        let route1 = place("Route1", lon: 0.005)
        let route2 = place("Route2", lon: 0.006)
        let wishlist1 = place("Wishlist1", lon: 0.05, status: .wantToGo)
        let wishlist2 = place("Wishlist2", lon: 0.06, status: .wantToGo)
        let wishlist3 = place("Wishlist3", lon: 0.07, status: .wantToGo)

        var rng = DeterministicRNG(state: 42)
        let stops = ItineraryPlanner.generate(
            from: [route1, route2, wishlist1, wishlist2, wishlist3],
            vibe: .relaxed,
            origin: origin,
            stopCount: 2,
            maxDistanceKm: 10,
            using: &rng
        )

        let mysteryStops = stops.filter(\.isMysteryStop)
        #expect(mysteryStops.count == 1)
        let mystery = try #require(mysteryStops.first)
        #expect(mystery.memory.visitStatus == .wantToGo)
        #expect(!stops.filter { !$0.isMysteryStop }.contains { $0.id == mystery.id })
    }

    @Test func generateHasNoMysteryStopWithoutWishlistPlaces() {
        let route1 = place("Route1", lon: 0.005, status: .beenThere)
        let route2 = place("Route2", lon: 0.006, status: .beenThere)
        let stops = ItineraryPlanner.generate(from: [route1, route2], vibe: .relaxed, origin: origin, stopCount: 2)
        #expect(stops.allSatisfy { !$0.isMysteryStop })
    }

    @Test func vibeWeightsFavorMatchingCategories() {
        #expect(ItineraryVibe.foodie.weight(for: .restaurant) > ItineraryVibe.foodie.weight(for: .hotel))
        #expect(ItineraryVibe.adventure.weight(for: .location) > ItineraryVibe.adventure.weight(for: .cafe))
    }

    @Test func mysteryVibePrefersWishlistOverBeenThere() {
        let wishlist = place("Wishlist", lon: 0.005, rating: 3, status: .wantToGo)
        let beenThere = place("BeenThere", lon: 0.005, rating: 3, status: .beenThere)
        let stops = ItineraryPlanner.generate(from: [wishlist, beenThere], vibe: .mystery, origin: origin, stopCount: 1)
        #expect(stops.first?.memory.name == "Wishlist")
    }

    @Test func mysteryVibePrefersLowerRatedOverHigherRated() {
        let lowRated = place("LowRated", lon: 0.005, rating: 1, status: .beenThere)
        let highRated = place("HighRated", lon: 0.005, rating: 5, status: .beenThere)
        let stops = ItineraryPlanner.generate(from: [lowRated, highRated], vibe: .mystery, origin: origin, stopCount: 1)
        #expect(stops.first?.memory.name == "LowRated")
    }

    @Test func mysteryVibeIgnoresCategory() {
        // Category shouldn't matter for .mystery — same rating/status/distance,
        // different categories, should score identically (order is a tie).
        let restaurant = place("Restaurant", lon: 0.005, category: .restaurant, rating: 3)
        let hotel = place("Hotel", lon: 0.005, category: .hotel, rating: 3)
        #expect(ItineraryVibe.mystery.score(for: restaurant, distanceKm: 1) == ItineraryVibe.mystery.score(for: hotel, distanceKm: 1))
    }

    @Test func glutenFreeOnlyExcludesNonGlutenFreeFoodPlaces() {
        let glutenFreeCafe = place("GF Cafe", lon: 0.005, category: .cafe, isGlutenFree: true)
        let regularCafe = place("Regular Cafe", lon: 0.006, category: .cafe, isGlutenFree: false)

        let stops = ItineraryPlanner.generate(from: [glutenFreeCafe, regularCafe], vibe: .relaxed, origin: origin, stopCount: 3, glutenFreeOnly: true)
        let names = stops.filter { !$0.isMysteryStop }.map(\.memory.name)
        #expect(names == ["GF Cafe"])
    }

    @Test func glutenFreeOnlyNeverExcludesNonFoodCategories() {
        let hotel = place("Hotel", lon: 0.005, category: .hotel, isGlutenFree: false)
        let location = place("Location", lon: 0.006, category: .location, isGlutenFree: false)

        let stops = ItineraryPlanner.generate(from: [hotel, location], vibe: .relaxed, origin: origin, stopCount: 3, glutenFreeOnly: true)
        let names = Set(stops.filter { !$0.isMysteryStop }.map(\.memory.name))
        #expect(names == ["Hotel", "Location"])
    }

    @Test func generateExcludesPlacesBeyondMaxDistance() {
        let near = place("Near", lon: 0.01)   // ~1.1 km
        let far = place("Far", lon: 0.05)     // ~5.6 km

        let stops = ItineraryPlanner.generate(from: [near, far], vibe: .relaxed, origin: origin, stopCount: 3, maxDistanceKm: 2)
        let names = stops.filter { !$0.isMysteryStop }.map(\.memory.name)
        #expect(names == ["Near"])
    }

    @Test func generateDefaultMaxDistanceIsFiveKm() {
        let near = place("Near", lon: 0.01)   // ~1.1 km
        let veryFar = place("VeryFar", lon: 0.5) // ~55.7 km, well past the default

        let stops = ItineraryPlanner.generate(from: [near, veryFar], vibe: .relaxed, origin: origin, stopCount: 3)
        let names = stops.filter { !$0.isMysteryStop }.map(\.memory.name)
        #expect(names == ["Near"])
    }

    @Test func topRatedRestaurantsOnlyExcludesLowerRatedRestaurants() {
        let greatRestaurant = place("Great", lon: 0.005, category: .restaurant, rating: 4)
        let mehRestaurant = place("Meh", lon: 0.006, category: .restaurant, rating: 3)

        let stops = ItineraryPlanner.generate(from: [greatRestaurant, mehRestaurant], vibe: .foodie, origin: origin, stopCount: 3, topRatedRestaurantsOnly: true)
        let names = stops.filter { !$0.isMysteryStop }.map(\.memory.name)
        #expect(names == ["Great"])
    }

    @Test func topRatedRestaurantsOnlyNeverExcludesNonRestaurantCategories() {
        let cafe = place("Cafe", lon: 0.005, category: .cafe, rating: 2)
        let hotel = place("Hotel", lon: 0.006, category: .hotel, rating: 1)

        let stops = ItineraryPlanner.generate(from: [cafe, hotel], vibe: .relaxed, origin: origin, stopCount: 3, topRatedRestaurantsOnly: true)
        let names = Set(stops.filter { !$0.isMysteryStop }.map(\.memory.name))
        #expect(names == ["Cafe", "Hotel"])
    }

    @Test func topRatedRestaurantsOnlyOffIncludesEverything() {
        let greatRestaurant = place("Great", lon: 0.005, category: .restaurant, rating: 4)
        let mehRestaurant = place("Meh", lon: 0.006, category: .restaurant, rating: 3)

        let stops = ItineraryPlanner.generate(from: [greatRestaurant, mehRestaurant], vibe: .foodie, origin: origin, stopCount: 3, topRatedRestaurantsOnly: false)
        let names = Set(stops.filter { !$0.isMysteryStop }.map(\.memory.name))
        #expect(names == ["Great", "Meh"])
    }

    @Test func glutenFreeOnlyOffIncludesEverything() {
        let glutenFreeCafe = place("GF Cafe", lon: 0.005, category: .cafe, isGlutenFree: true)
        let regularCafe = place("Regular Cafe", lon: 0.006, category: .cafe, isGlutenFree: false)

        let stops = ItineraryPlanner.generate(from: [glutenFreeCafe, regularCafe], vibe: .relaxed, origin: origin, stopCount: 3, glutenFreeOnly: false)
        let names = Set(stops.filter { !$0.isMysteryStop }.map(\.memory.name))
        #expect(names == ["GF Cafe", "Regular Cafe"])
    }
}
