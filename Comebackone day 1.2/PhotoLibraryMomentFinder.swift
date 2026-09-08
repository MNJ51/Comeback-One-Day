//
//  PhotoLibraryMomentFinder.swift
//  Comebackone day 1.2
//
//  Scans the user's Photos library for recent same-day, same-place photo
//  clusters ("moments"), Apple Journal-style, and offers them as journal
//  entry suggestions. Uses the raw Photos framework (not PhotosUI's
//  out-of-process PhotosPicker used elsewhere in the app) because it needs
//  to see asset metadata — capture date, location — before the user picks
//  anything, which requires an explicit NSPhotoLibraryUsageDescription
//  permission prompt.
//

import CoreLocation
import Photos
import UIKit

/// A cluster of same-day, nearby-location photos suggested as one journal
/// entry, mirroring how a Smart Suggestion card links to a saved place.
struct PhotoMoment: Identifiable {
    let id = UUID()
    let date: Date
    let coordinate: CLLocationCoordinate2D?
    var locationLabel: String?
    let assetIdentifiers: [String]
}

enum PhotoLibraryMomentFinder {
    /// How far back to look for moments — recent enough to still be worth
    /// journaling about.
    private static let lookbackDays = 60
    /// Same-day photos within this distance of each other are one moment.
    private static let clusterRadiusMeters: CLLocationDistance = 500
    private static let maxAssetsScanned = 300
    private static let maxMomentsReturned = 5

    static var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Finds recent moments not already covered by an existing journal
    /// entry's linked photos, so a suggestion never re-offers something the
    /// user already journaled about.
    static func findMoments(excludingAssetIdentifiers excluded: Set<String> = []) async -> [PhotoMoment] {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return [] }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let cutoff = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date.distantPast
        options.predicate = NSPredicate(format: "mediaType == %d AND creationDate >= %@", PHAssetMediaType.image.rawValue, cutoff as NSDate)
        options.fetchLimit = maxAssetsScanned

        let fetchResult = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            if !excluded.contains(asset.localIdentifier) {
                assets.append(asset)
            }
        }

        let clusters = cluster(assets)
        var moments = clusters.prefix(maxMomentsReturned).map { cluster -> PhotoMoment in
            PhotoMoment(
                date: cluster.first?.creationDate ?? Date(),
                coordinate: cluster.first(where: { $0.location != nil })?.location?.coordinate,
                locationLabel: nil,
                assetIdentifiers: cluster.map(\.localIdentifier)
            )
        }

        let labels = await withTaskGroup(of: (Int, String?).self) { group in
            for index in moments.indices {
                guard let coordinate = moments[index].coordinate else { continue }
                group.addTask { (index, await LocationSearchService.shortLabel(for: coordinate)) }
            }
            var results: [Int: String?] = [:]
            for await (index, label) in group { results[index] = label }
            return results
        }
        for (index, label) in labels {
            moments[index].locationLabel = label
        }
        return moments
    }

    /// Greedy same-calendar-day + within-`clusterRadiusMeters` grouping.
    private static func cluster(_ assets: [PHAsset]) -> [[PHAsset]] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: assets) { asset in
            calendar.startOfDay(for: asset.creationDate ?? Date())
        }

        var clusters: [[PHAsset]] = []
        for day in byDay.keys.sorted(by: >) {
            guard let dayAssets = byDay[day] else { continue }
            clusters.append(contentsOf: clusterByLocation(dayAssets))
        }
        return clusters
    }

    private static func clusterByLocation(_ assets: [PHAsset]) -> [[PHAsset]] {
        var remaining = assets
        var result: [[PHAsset]] = []

        while !remaining.isEmpty {
            let seed = remaining.removeFirst()
            var group = [seed]
            if let seedLocation = seed.location {
                remaining.removeAll { candidate in
                    guard let candidateLocation = candidate.location else { return false }
                    guard seedLocation.distance(from: candidateLocation) <= clusterRadiusMeters else { return false }
                    group.append(candidate)
                    return true
                }
            }
            result.append(group)
        }
        return result
    }

    /// Loads full-resolution JPEG data for a picked moment's assets, for
    /// attaching to a new journal entry the same way a PhotosPicker
    /// selection is handled.
    static func loadImageData(for assetIdentifiers: [String]) async -> [Data] {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in assets.append(asset) }

        let indexedResults = await withTaskGroup(of: (Int, Data?).self) { group in
            for (index, asset) in assets.enumerated() {
                group.addTask { (index, await requestImageData(for: asset)) }
            }
            var results: [Int: Data] = [:]
            for await (index, data) in group {
                if let data { results[index] = data }
            }
            return results
        }
        return indexedResults.keys.sorted().compactMap { indexedResults[$0] }
    }

    private static func requestImageData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// A small collage thumbnail (first asset in the moment) for the
    /// suggestion card.
    static func thumbnail(for assetIdentifier: String, maxDimension: CGFloat) async -> UIImage? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            // .highQualityFormat (not .opportunistic) delivers exactly once —
            // .opportunistic can call this handler twice, which would double-
            // resume the continuation and crash.
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isSynchronous = false
            let targetSize = CGSize(width: maxDimension * 3, height: maxDimension * 3)
            PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
