//
//  JournalAppearance.swift
//  Comebackone day 1.2
//
//  A journal's color + icon, Apple Journal-style — purely cosmetic metadata
//  keyed by journal name, not a new managed entity. `journalName` on
//  JournalEntry stays the only source of truth for what journal an entry
//  belongs to (JournalModels.swift); this just decorates that free-text tag.
//  Local-only, no CloudKit sync — decoration isn't worth a third sync engine.
//

import SwiftUI
import Combine

enum JournalColorOption: String, CaseIterable, Codable, Identifiable {
    case plum, red, magenta, coral, tan, orange, green,
         cyan, blue, steelBlue, periwinkle, purple, black

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .plum: return Color(red: 0.62, green: 0.18, blue: 0.55)
        case .red: return Color(red: 0.93, green: 0.26, blue: 0.21)
        case .magenta: return Color(red: 0.87, green: 0.36, blue: 0.84)
        case .coral: return Color(red: 0.92, green: 0.48, blue: 0.44)
        case .tan: return Color(red: 0.78, green: 0.55, blue: 0.42)
        case .orange: return Color(red: 0.98, green: 0.60, blue: 0.20)
        case .green: return Color(red: 0.16, green: 0.75, blue: 0.52)
        case .cyan: return Color(red: 0.15, green: 0.75, blue: 0.85)
        case .blue: return Color(red: 0.20, green: 0.35, blue: 0.85)
        case .steelBlue: return Color(red: 0.45, green: 0.58, blue: 0.68)
        case .periwinkle: return Color(red: 0.45, green: 0.55, blue: 0.95)
        case .purple: return Color(red: 0.5, green: 0.42, blue: 0.88)
        case .black: return .black
        }
    }
}

/// A journal's chosen color and SF Symbol icon. `customColorHex` overrides
/// `color` when set — from the picker's rainbow "custom" swatch, which
/// isn't one of the fixed `JournalColorOption` cases.
struct JournalAppearance: Codable, Equatable {
    var color: JournalColorOption
    var customColorHex: String?
    var iconName: String

    static let `default` = JournalAppearance(color: .plum, iconName: "book.closed.fill")

    var resolvedColor: Color {
        if let customColorHex, let parsed = Color(hex: customColorHex) {
            return parsed
        }
        return color.color
    }
}

extension Color {
    /// Parses a `#RRGGBB` (or `RRGGBB`) hex string; nil for anything malformed.
    init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self = Color(red: red, green: green, blue: blue)
    }

    /// The `#RRGGBB` hex string for this color, resolved in the standard
    /// (non-wide-gamut) sRGB space — good enough for a saved UI preference.
    var hexString: String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        // .rounded(), not truncation — a value like 152.9999... from the
        // color-space conversion must still land on 153 (0x99), or a
        // hex -> Color -> hex round-trip can drift by one hex digit.
        return String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}

/// Curated icon set for the journal-creation picker, spanning the same
/// rough categories Apple Journal's own grid does (people, home, travel,
/// food, nature, weather, animals) — all standard SF Symbols.
enum JournalIconOptions {
    static let all: [String] = [
        "face.smiling", "shippingbox.fill", "house.fill", "bed.double.fill",
        "fork.knife", "books.vertical.fill", "phone.fill", "key.fill",
        "puzzlepiece.fill", "lightbulb.fill", "airplane", "map.fill",
        "mappin.and.ellipse", "globe", "car.fill", "bicycle",
        "sailboat.fill", "suitcase.fill", "tent.fill", "signpost.right.fill",
        "camera.fill", "bus.fill", "tram.fill", "cup.and.saucer.fill",
        "wineglass.fill", "birthday.cake.fill", "basket.fill", "mountain.2.fill",
        "sun.max.fill", "snowflake", "bolt.fill", "moon.fill",
        "cloud.rain.fill", "flame.fill", "rainbow", "leaf.fill",
        "tree.fill", "binoculars.fill", "pawprint.fill", "bird.fill",
        "tortoise.fill", "figure.walk", "figure.2", "heart.fill",
        "star.fill", "gift.fill", "music.note", "gamecontroller.fill",
        "paintpalette.fill", "dumbbell.fill", "umbrella.fill"
    ]
}

/// Local-only (no CloudKit sync). Same load/save-on-change persistence
/// shape as JournalStore, minus the sync manager — this is decoration, not
/// data worth syncing across devices via a third CKSyncEngine.
final class JournalAppearanceStore: ObservableObject {
    @Published var appearances: [String: JournalAppearance] = [:] { didSet { save() } }

    private var isLoading = false
    private let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("journal-appearances.json")

    init() {
        load()
    }

    func appearance(for journalName: String) -> JournalAppearance {
        appearances[journalName] ?? .default
    }

    private func save() {
        guard !isLoading else { return }
        if let encoded = try? JSONEncoder().encode(appearances) {
            try? encoded.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: JournalAppearance].self, from: data) {
            appearances = decoded
        }
    }
}
