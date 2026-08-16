# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Come Back One Day" — a SwiftUI iOS app for saving places you want to revisit (restaurants, bars, hotels, markets, general locations), pinned on a map with photos, ratings, and notes.

Note: the repo folder is named `Comebackone day 1.2`, but the Xcode project, targets, schemes, bundle identifiers, and source folder inside it are all still named `Comebackone day 1.1` (this is a working copy for v2 development). Use the `1.1` names in build commands below — don't assume they've been renamed.

## Commands

Build for the simulator:
```bash
xcodebuild -project "Comebackone day 1.1.xcodeproj" -scheme "Comebackone day 1.1" -destination 'generic/platform=iOS Simulator' build
```

Run unit tests (Swift Testing framework, target `Comebackone day 1.1Tests`):
```bash
xcodebuild test -project "Comebackone day 1.1.xcodeproj" -scheme "Comebackone day 1.1" -destination 'platform=iOS Simulator,name=iPhone 16'
```

Run a single test:
```bash
xcodebuild test -project "Comebackone day 1.1.xcodeproj" -scheme "Comebackone day 1.1" -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:"Comebackone day 1.1Tests/TravelMemoryCodingTests/roundTripPreservesAllFields"
```

There are no shared (`.xcscheme`) schemes checked into the project — Xcode/xcodebuild generates the default scheme from the target name automatically.

## Architecture

**Data model** ([Models.swift](Comebackone day 1.1/Models.swift)): `TravelMemory` is the core struct — a saved place with coordinates, category, photos, rating, notes, and visit date. Its `Codable` implementation is hand-written to stay backward-compatible with older JSON shapes (e.g. a single `photoFilename` string migrating to `photoFilenames: [String]`) — when adding fields, extend the custom `init(from:)`/`encode(to:)` rather than relying on synthesized conformance, and add a decode test alongside the existing ones in `Comebackone day 1.1Tests`.

`TravelMemory` also encodes/decodes itself as a `comebackoneday://add?...` deep link (see the "Sharing places as a deep link" extension) so one user can share a place with another. Photos are never included in the link.

**Persistence** ([MemoryStore.swift](Comebackone day 1.1/MemoryStore.swift)): `MemoryStore` is an `ObservableObject` holding the in-memory `[TravelMemory]` array, injected app-wide via `.environmentObject` from `ContentView`. Every mutation writes the full array to `memories.json` in the Documents directory. It also migrates legacy data that very old builds stored in `UserDefaults` (with photo bytes inline) on first launch.

**iCloud sync** ([CloudSyncManager.swift](Comebackone day 1.1/CloudSyncManager.swift)): owned by `MemoryStore`, syncs to the user's private CloudKit database via `CKSyncEngine` (one record per memory in a custom zone, photos as `CKAsset`). It's offline-first — the engine queues and retries changes locally, and everything still works with no iCloud account. `MemoryStore.add/update/delete` queue sync work; `applyRemoteSave/applyRemoteDelete` apply incoming changes from CloudKit *without* re-queuing them (important invariant — don't call the queueing methods from remote-apply paths, or you'll create sync loops).

**Photos** ([PhotoStore.swift](Comebackone day 1.1/PhotoStore.swift)): photos are stored as JPEG files on disk in `Documents/Photos`, downscaled on save; `TravelMemory` only holds filenames. Thumbnails are decoded via ImageIO (not `UIImage`) and cached in an `NSCache`, so full-size images are never loaded just to render a pin or list row.

**UI**: `ContentView` hosts a `TabView` (Map / Places) and owns the shared `MemoryStore` and `LocationManager`, handling `onOpenURL` for deep-link imports. `MapTabView` shows the map with category filter chips and buttons to add a place manually (`AddMemoryView`) or via quick camera capture (`QuickCameraView`). `LocationSearchService` wraps `MKLocalSearchCompleter` for place-name search in the add/edit forms.

## Bundle identifiers

- App: `com.michaeljee.Comebackone-day-1-1`
- iCloud container: `iCloud.com.michaeljee.Comebackone-day-1-1`
- URL scheme for shared-place deep links: `comebackoneday`

Deployment target is iOS 18, iPhone-only (`TARGETED_DEVICE_FAMILY = 1`).
