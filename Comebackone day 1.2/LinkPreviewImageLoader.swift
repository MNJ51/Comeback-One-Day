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
//  LPMetadataProvider renders the target page internally (it's WebKit-backed)
//  to read its metadata, which is expensive. Two things matter here: never
//  run more than one fetch at a time (an itinerary with several stops firing
//  this concurrently is what got the app jetsam-killed on an older device),
//  and never keep a fetched image at its full decoded resolution once cached
//  — this downscales after decoding, same idea as PhotoStore's thumbnails,
//  just working from an already-decoded UIImage rather than raw file data,
//  since NSItemProvider.loadDataRepresentation is unreliable against
//  LPLinkMetadata's imageProvider (its type identifier is often a dynamic/
//  placeholder UTI) — loadObject(ofClass:) is the form that actually works.
//

import LinkPresentation
import UIKit

actor LinkPreviewImageLoader {
    static let shared = LinkPreviewImageLoader()

    private let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 30
        return cache
    }()
    /// The tail of a chain of tasks, one per request. Each new request awaits
    /// whichever task was the tail when it arrived, then becomes the new
    /// tail itself — a standard task-chaining queue. Callers never poll or
    /// re-check a task that's already finished, so this can't spin the way a
    /// "while there's something in flight, re-await it" loop can.
    private var tail: Task<UIImage?, Never>?

    /// Returns nil if the site has no preview image, times out, or fails —
    /// callers should treat that as "no photo available," not an error. Only
    /// one fetch runs at a time; concurrent callers for different URLs queue
    /// behind each other rather than piling up simultaneous page renders.
    func image(for url: URL, maxDimension: CGFloat = 400) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        let previousTail = tail
        let newTail = Task<UIImage?, Never> { [cache] in
            _ = await previousTail?.value
            if let cached = cache.object(forKey: url as NSURL) {
                return cached
            }
            let result = await Self.fetchAndDownscale(url: url, maxDimension: maxDimension)
            if let result {
                cache.setObject(result, forKey: url as NSURL)
            }
            return result
        }
        tail = newTail
        return await newTail.value
    }

    /// Races the actual fetch against a hard timeout, so a hung or
    /// unresponsive site can't stall every other stop's photo behind it —
    /// LPMetadataProvider.timeout only covers the metadata phase, not
    /// necessarily the image-loading phase that follows it.
    private static func fetchAndDownscale(url: URL, maxDimension: CGFloat) async -> UIImage? {
        await withTaskGroup(of: UIImage?.self) { group in
            group.addTask {
                let provider = LPMetadataProvider()
                provider.timeout = 8
                guard let metadata = try? await provider.startFetchingMetadata(for: url),
                      let imageProvider = metadata.imageProvider,
                      let image = await loadImage(from: imageProvider) else {
                    return nil
                }
                return downscaled(image, maxDimension: maxDimension)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private static func loadImage(from provider: NSItemProvider) async -> UIImage? {
        guard provider.canLoadObject(ofClass: UIImage.self) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }

    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > maxDimension else { return image }
        let scale = maxDimension / largestSide
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
