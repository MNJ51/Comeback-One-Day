//
//  PhotoStore.swift
//  Comebackone day 1.1
//
//  Photos live as JPEG files in Documents/Photos; memories store only the filename.
//

import UIKit
import ImageIO

enum PhotoStore {
    private static let cache = NSCache<NSString, UIImage>()

    static var photosDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for filename: String) -> URL {
        photosDirectory.appendingPathComponent(filename)
    }

    /// Saves JPEG data to disk (downscaled to a sane size) and returns the filename.
    static func save(_ data: Data) -> String? {
        let filename = UUID().uuidString + ".jpg"
        let finalData = downscaledJPEG(from: data) ?? data
        do {
            try finalData.write(to: url(for: filename))
            return filename
        } catch {
            return nil
        }
    }

    static func image(for filename: String?) -> UIImage? {
        guard let filename else { return nil }
        return UIImage(contentsOfFile: url(for: filename).path)
    }

    /// Small cached thumbnail for map pins and list rows, decoded via ImageIO
    /// so the full-size photo never has to be loaded into memory.
    static func thumbnail(for filename: String?, maxDimension: CGFloat = 120) -> UIImage? {
        guard let filename else { return nil }
        let key = "\(filename)-\(Int(maxDimension))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // 3x covers the densest iPhone displays
            kCGImageSourceThumbnailMaxPixelSize: maxDimension * 3
        ]
        guard let source = CGImageSourceCreateWithURL(url(for: filename) as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let thumbnail = UIImage(cgImage: cgImage)
        cache.setObject(thumbnail, forKey: key)
        return thumbnail
    }

    static func delete(_ filename: String?) {
        guard let filename else { return }
        try? FileManager.default.removeItem(at: url(for: filename))
        cache.removeAllObjects()
    }

    static func delete(_ filenames: [String]) {
        for filename in filenames {
            try? FileManager.default.removeItem(at: url(for: filename))
        }
        cache.removeAllObjects()
    }

    private static func downscaledJPEG(from data: Data, maxDimension: CGFloat = 2048) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > maxDimension else {
            return image.jpegData(compressionQuality: 0.8)
        }
        let scale = maxDimension / largestSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
