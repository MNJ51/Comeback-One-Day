# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Come Back One Day" — a SwiftUI iOS app for saving places you want to revisit (restaurants, bars, hotels, markets, general locations), pinned on a map with photos, ratings, and notes.

This folder is a **git worktree**: it's the `v2` branch of the same repo as the sibling `../Comebackone day 1.1` folder (which stays on `main`, untouched). They share one `.git` history, so a fix made here can be cherry-picked back to `main` (or vice versa) with normal git commands — there's no separate remote or independent repo to keep in sync.

The Xcode project, targets, scheme, and source folder are all named `Comebackone day 1.2` to match. The bundle ID, iCloud container ID, and `comebackoneday://` URL scheme were deliberately **left unchanged** from v1.1 (see "Bundle identifiers" below) so this remains the same app/CloudKit data on the App Store, not a fork — don't rename those without a deliberate reason.

## Commands

This project uses CocoaPods (for `FBAudienceNetwork`, which has no SPM distribution — see "Monetization" below), so **build against the `.xcworkspace`, not the bare `.xcodeproj`**, from here on:

Build for the simulator:
```bash
xcodebuild -workspace "Comebackone day 1.2.xcworkspace" -scheme "Comebackone day 1.2" -destination 'generic/platform=iOS Simulator' build
```

Run unit tests (Swift Testing framework, target `Comebackone day 1.2Tests`):
```bash
xcodebuild test -workspace "Comebackone day 1.2.xcworkspace" -scheme "Comebackone day 1.2" -destination 'id=CF6D6D49-5427-44AF-965A-E49F58681583'
```

Run a single test:
```bash
xcodebuild test -workspace "Comebackone day 1.2.xcworkspace" -scheme "Comebackone day 1.2" -destination 'id=CF6D6D49-5427-44AF-965A-E49F58681583' -only-testing:"Comebackone day 1.2Tests/TravelMemoryCodingTests/roundTripPreservesAllFields"
```

The destination above is a UDID for an installed iPhone 17 Pro simulator (`xcrun simctl list devices available` to see what's actually installed on this Mac — device names/UDIDs vary by machine).

There are no shared (`.xcscheme`) schemes checked into the project — Xcode/xcodebuild generates the default scheme from the target name automatically.

After pulling `Podfile`/`Podfile.lock` changes, re-run `pod install` before building. CocoaPods needs a modern Ruby (macOS's built-in system Ruby, 2.6.x, is too old for current CocoaPods and several of its stdlib gem dependencies) — this machine's CocoaPods is installed under Homebrew's Ruby: `/opt/homebrew/lib/ruby/gems/4.0.0/bin/pod install`. The Xcode project also has `ENABLE_USER_SCRIPT_SANDBOXING = NO` (both Debug/Release configs) — CocoaPods' `[CP] Embed Pods Frameworks` script phase fails under Xcode's newer script-sandboxing with a vendored `.xcframework` pod like `FBAudienceNetwork`; don't re-enable it without re-testing that phase.

## Architecture

**Data model** ([Models.swift](Comebackone day 1.2/Models.swift)): `TravelMemory` is the core struct — a saved place with coordinates, category, photos, rating, notes, and visit date. Its `Codable` implementation is hand-written to stay backward-compatible with older JSON shapes (e.g. a single `photoFilename` string migrating to `photoFilenames: [String]`) — when adding fields, extend the custom `init(from:)`/`encode(to:)` rather than relying on synthesized conformance, and add a decode test alongside the existing ones in `Comebackone day 1.2Tests`.

`TravelMemory` also encodes/decodes itself as a shared-place deep link (see the "Sharing places as a deep link" extension) so one user can share a place with another. Photos are never included in the link. `shareURL` produces a Universal Link (`https://www.thehealthclubonline.com/comebackonedayapp/add?...`) so the link falls back to the app's landing page when the recipient doesn't have the app installed yet; `init?(shareURL:)` still decodes the older `comebackoneday://add?...` custom-scheme links so ones shared before this change keep working. See "Universal Links" below for the server-side half of this.

**Persistence** ([MemoryStore.swift](Comebackone day 1.2/MemoryStore.swift)): `MemoryStore` is an `ObservableObject` holding the in-memory `[TravelMemory]` array, injected app-wide via `.environmentObject` from `ContentView`. Every mutation writes the full array to `memories.json` in the Documents directory. It also migrates legacy data that very old builds stored in `UserDefaults` (with photo bytes inline) on first launch.

**iCloud sync** ([CloudSyncManager.swift](Comebackone day 1.2/CloudSyncManager.swift)): owned by `MemoryStore`, syncs to the user's private CloudKit database via `CKSyncEngine` (one record per memory in a custom zone, photos as `CKAsset`). It's offline-first — the engine queues and retries changes locally, and everything still works with no iCloud account. `MemoryStore.add/update/delete` queue sync work; `applyRemoteSave/applyRemoteDelete` apply incoming changes from CloudKit *without* re-queuing them (important invariant — don't call the queueing methods from remote-apply paths, or you'll create sync loops).

**Photos** ([PhotoStore.swift](Comebackone day 1.2/PhotoStore.swift)): photos are stored as JPEG files on disk in `Documents/Photos`, downscaled on save; `TravelMemory` only holds filenames. Thumbnails are decoded via ImageIO (not `UIImage`) and cached in an `NSCache`, so full-size images are never loaded just to render a pin or list row.

**UI**: `ContentView` hosts a `TabView` (Map / Places / Journal) and owns the shared `MemoryStore` and `LocationManager`, handling `onOpenURL` for deep-link imports. `MapTabView` shows the map with category filter chips and buttons to add a place manually (`AddMemoryView`) or via quick camera capture (`QuickCameraView`). `LocationSearchService` wraps `MKLocalSearchCompleter` for place-name search in the add/edit forms.

**Monetization** ([AdsManager.swift](Comebackone day 1.2/AdsManager.swift), [SubscriptionManager.swift](Comebackone day 1.2/SubscriptionManager.swift)): the app is free to download. `AdsManager` starts the Meta Audience Network SDK (`FBAudienceNetwork`, added via CocoaPods — no official SPM distribution exists for it, see "Commands" above) and owns the StoreKit 2 non-consumable "Remove Ads" purchase (`com.michaeljee.Comebackone-day-1-1.removeads`); `SubscriptionManager` is the separate auto-renewing "Itinerary Plus" subscription that unlocks day-itinerary generation — both follow the same StoreKit 2 load/purchase/restore pattern and both need their product created in App Store Connect before they'll load for real (`Configuration.storekit` at the project root has both wired up for local testing without that — Xcode: Product > Scheme > Edit Scheme > Run > Options > StoreKit Configuration). `BannerAdView.swift`'s `AdBanner` wraps `FBAdView` and hides itself once `AdsManager.isAdRemoved` is true; it's rendered directly in `ContentView`'s bottom overlay (alongside `BottomActionBar`), *not* nested inside `MapTabView`/`MemoryListView` — a `safeAreaInset` added from inside a `TabView` page lays out correctly (non-zero, non-hidden frame) but never actually paints, silently clipped by the page's own container. `AdsManager.bannerPlacementID` is a placeholder — swap in a real Meta Audience Network placement ID before shipping (the Simulator gets test ads automatically regardless of placement ID; a real device needs `FBAdSettings.addTestDevice(...)` once). Meta Audience Network has been bidding-only since 2024 — `BannerAdView` still calls `FBAdView`'s deprecated `loadAd()` since no server-side bidding integration exists here; moving to `loadAdWithBidPayload:` (via a mediation partner or your own bidding endpoint) is a real prerequisite for serving genuine (non-test) ads in production, not something already wired up. Meta Audience Network has no request-level contextual-targeting equivalent to AdMob's old `GADRequest.keywords`.

## Bundle identifiers

- App: `com.michaeljee.Comebackone-day-1-1`
- iCloud container: `iCloud.com.michaeljee.Comebackone-day-1-1`
- URL scheme for shared-place deep links (legacy, still decoded): `comebackoneday`
- Team ID: `KG2C627Z62`

Deployment target is iOS 18, iPhone-only (`TARGETED_DEVICE_FAMILY = 1`).

## Universal Links

Shared-place links (`TravelMemory.shareURL`) point at `https://www.thehealthclubonline.com/comebackonedayapp/add?...`, the same domain hosting the app's marketing/download landing page (`/comebackonedayapp/`). The app declares `applinks:www.thehealthclubonline.com` and `applinks:thehealthclubonline.com` in [Comebackone day 1.2.entitlements](Comebackone day 1.2/Comebackone day 1.2.entitlements) (Associated Domains).

For iOS to route those links into the app instead of Safari, the domain must serve [web/apple-app-site-association](web/apple-app-site-association) — a file that is **not part of the Xcode project**, since it has to live at `https://www.thehealthclubonline.com/.well-known/apple-app-site-association` (and the same path on the bare domain) on the actual web server, served over HTTPS with no redirects. It scopes matching to `/comebackonedayapp/add*` only, so the rest of that site (the landing page itself) is unaffected. If the AASA content or the Team ID/bundle ID ever changes, update that file both here and on the live server — they'll drift silently otherwise, since nothing in this repo deploys it automatically.
