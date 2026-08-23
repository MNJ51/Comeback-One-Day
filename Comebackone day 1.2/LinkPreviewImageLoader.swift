//
//  LinkPreviewImageLoader.swift
//  Comebackone day 1.2
//
//  Fetches a real photo for a discovered place from its own website's link
//  preview metadata — the same Open Graph-style data Messages/Safari use to
//  show a rich preview image for a link. This is a free, legitimate stand-in
//  for a paid places API: MapKit itself exposes no business photos, but many
//  business websites publish their own preview image, and LinkPresentation
//  is a public Apple framework for reading it — no account, no key, no cost.
//

import LinkPresentation
import UIKit

enum LinkPreviewImageLoader {
    private static let cache = NSCache<NSURL, UIImage>()

    /// Returns nil if the site has no preview image, times out, or fails —
    /// callers should treat that as "no photo available," not an error.
    static func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        guard let metadata = try? await LPMetadataProvider().startFetchingMetadata(for: url),
              let imageProvider = metadata.imageProvider,
              let image = await loadImage(from: imageProvider) else {
            return nil
        }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    private static func loadImage(from provider: NSItemProvider) async -> UIImage? {
        guard provider.canLoadObject(ofClass: UIImage.self) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }
}
