//
//  DrawingStore.swift
//  Comebackone day 1.2
//
//  Sketches live as PKDrawing-archived files in Documents/Drawings; entries
//  store only the filename, mirroring how PhotoStore/VoiceNoteStore handle
//  photos and audio.
//

import PencilKit
import UIKit

enum DrawingStore {
    private static let thumbnailCache = NSCache<NSString, UIImage>()

    static var drawingsDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Drawings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for filename: String) -> URL {
        drawingsDirectory.appendingPathComponent(filename)
    }

    static func newFilename() -> String {
        UUID().uuidString + ".drawing"
    }

    /// Saves a PKDrawing's archived data to disk and returns the filename.
    static func save(_ drawing: PKDrawing) -> String? {
        let filename = newFilename()
        do {
            try drawing.dataRepresentation().write(to: url(for: filename))
            return filename
        } catch {
            return nil
        }
    }

    static func drawing(for filename: String?) -> PKDrawing? {
        guard let filename, let data = try? Data(contentsOf: url(for: filename)) else { return nil }
        return try? PKDrawing(data: data)
    }

    /// A cached raster thumbnail for entry cards — rendering a PKDrawing to
    /// an image is comparatively expensive, so the result is cached the same
    /// way PhotoStore caches decoded photo thumbnails.
    static func thumbnail(for filename: String?, maxDimension: CGFloat = 160) -> UIImage? {
        guard let filename else { return nil }
        let key = "\(filename)-\(Int(maxDimension))" as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        guard let drawing = drawing(for: filename) else { return nil }
        let bounds = drawing.bounds.isEmpty ? CGRect(x: 0, y: 0, width: maxDimension, height: maxDimension) : drawing.bounds
        let largestSide = max(bounds.width, bounds.height)
        guard largestSide > 0 else { return nil }
        let scale = maxDimension / largestSide
        let image = drawing.image(from: bounds, scale: scale)
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    static func delete(_ filename: String?) {
        guard let filename else { return }
        try? FileManager.default.removeItem(at: url(for: filename))
        thumbnailCache.removeAllObjects()
    }
}
