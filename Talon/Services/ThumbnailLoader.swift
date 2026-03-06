import UIKit
import ImageIO

/// Actor that manages thumbnail loading with request merging and caching
actor ThumbnailLoader {
    private let cache = NSCache<NSString, UIImage>()
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]

    init() {
        cache.countLimit = 500
    }

    /// Load a thumbnail for the given asset, with request merging
    func loadThumbnail(assetID: String, thumbnailURL: URL, targetSize: CGSize) async -> UIImage? {
        let cacheKey = NSString(string: assetID)

        // Check memory cache
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        // Check for in-flight request (request merging)
        if let existing = inFlightTasks[assetID] {
            return await existing.value
        }

        // Create new loading task
        let task = Task<UIImage?, Never> {
            let image = await decodeThumbnail(at: thumbnailURL, targetSize: targetSize)
            if let image {
                cache.setObject(image, forKey: cacheKey)
            }
            return image
        }

        inFlightTasks[assetID] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: assetID)
        return result
    }

    /// Cancel loading for an asset (when view disappears)
    func cancelLoad(assetID: String) {
        inFlightTasks[assetID]?.cancel()
        inFlightTasks.removeValue(forKey: assetID)
    }

    /// Clear memory cache
    func clearCache() {
        cache.removeAllObjects()
    }

    /// Decode thumbnail using ImageIO for optimal performance
    private func decodeThumbnail(at url: URL, targetSize: CGSize) async -> UIImage? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let maxDimension = max(targetSize.width, targetSize.height) * UIScreen.main.scale
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }.value
    }
}
