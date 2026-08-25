//
//  VideoStore.swift
//  Comebackone day 1.2
//
//  Videos live as .mov files in Documents/Videos; memories store only the
//  filename, same pattern as PhotoStore. A picked or recorded video is
//  compressed on save (source clips can be huge) and a poster-frame
//  thumbnail is generated on demand via AVFoundation rather than decoding
//  the whole video just to show a preview.
//

import AVFoundation
import UIKit

enum VideoStore {
    private static let thumbnailCache = NSCache<NSString, UIImage>()

    static var videosDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for filename: String) -> URL {
        videosDirectory.appendingPathComponent(filename)
    }

    /// Compresses and copies a video from a temporary source file into
    /// permanent storage, returning the stored filename. Falls back to a
    /// plain copy if compression can't be set up for this asset.
    static func save(_ sourceURL: URL) async -> String? {
        let filename = UUID().uuidString + ".mov"
        let destination = url(for: filename)
        let asset = AVURLAsset(url: sourceURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            return (try? FileManager.default.copyItem(at: sourceURL, to: destination)) != nil ? filename : nil
        }
        do {
            try await export.export(to: destination, as: .mov)
            return filename
        } catch {
            return nil
        }
    }

    static func videoExists(_ filename: String?) -> Bool {
        guard let filename else { return false }
        return FileManager.default.fileExists(atPath: url(for: filename).path)
    }

    /// A poster-frame thumbnail for list rows and pins, generated from the
    /// first frame rather than requiring the video to be loaded/played.
    static func thumbnail(for filename: String?, maxDimension: CGFloat = 120) -> UIImage? {
        guard let filename else { return nil }
        return thumbnail(forFileAt: url(for: filename), cacheKey: filename, maxDimension: maxDimension)
    }

    /// Same as above, but for a video that hasn't been saved yet (e.g. a
    /// freshly picked/recorded clip still at its temporary source URL).
    static func thumbnail(forTemporaryFileAt fileURL: URL, maxDimension: CGFloat = 120) -> UIImage? {
        thumbnail(forFileAt: fileURL, cacheKey: fileURL.absoluteString, maxDimension: maxDimension)
    }

    private static func thumbnail(forFileAt fileURL: URL, cacheKey: String, maxDimension: CGFloat) -> UIImage? {
        let key = "\(cacheKey)-\(Int(maxDimension))" as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension * 3, height: maxDimension * 3)
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        let thumbnail = UIImage(cgImage: cgImage)
        thumbnailCache.setObject(thumbnail, forKey: key)
        return thumbnail
    }

    static func delete(_ filename: String?) {
        guard let filename else { return }
        try? FileManager.default.removeItem(at: url(for: filename))
    }

    static func delete(_ filenames: [String]) {
        for filename in filenames {
            try? FileManager.default.removeItem(at: url(for: filename))
        }
    }
}
