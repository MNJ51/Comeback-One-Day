//
//  WeatherService.swift
//  Comebackone day 1.2
//
//  Thin wrapper around WeatherKit for auto-tagging a journal entry with the
//  weather at the moment it's written. Requires the WeatherKit capability to
//  be enabled for this App ID (Signing & Capabilities in Xcode, or the App ID
//  configuration on developer.apple.com — it's included in the paid Apple
//  Developer Program, no separate signup or billing). Until that's enabled,
//  fetches simply fail and return nil rather than crashing, so a journal
//  entry never blocks on weather being unavailable.
//

import CoreLocation
import WeatherKit

struct EntryWeather {
    let temperatureCelsius: Double
    let symbolName: String
    let description: String
}

enum AppWeatherService {
    static func currentWeather(at coordinate: CLLocationCoordinate2D) async -> EntryWeather? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let weather = try? await WeatherService.shared.weather(for: location) else {
            return nil
        }
        let current = weather.currentWeather
        return EntryWeather(
            temperatureCelsius: current.temperature.converted(to: .celsius).value,
            symbolName: current.symbolName,
            description: current.condition.description
        )
    }
}
