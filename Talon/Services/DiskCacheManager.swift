import Foundation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.app",
    category: "DiskCacheManager"
)

/// Manages disk cache for thumbnails and original files
actor DiskCacheManager {
    private let cacheDirectory: URL
    private let maxCacheSize: Int64 // bytes

    init(maxCacheSizeMB: Int = 500) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = caches.appendingPathComponent("TalonImageCache", isDirectory: true)
        self.maxCacheSize = Int64(maxCacheSizeMB) * 1024 * 1024

        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Cache a thumbnail from a library URL to local cache
    func cacheThumbnail(assetID: String, sourceURL: URL) throws -> URL {
        let destURL = cacheDirectory.appendingPathComponent("thumb_\(assetID).png")
        guard !FileManager.default.fileExists(atPath: destURL.path) else { return destURL }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        logger.debug("Cached thumbnail: \(assetID)")
        return destURL
    }

    /// Get cached thumbnail URL if it exists
    func cachedThumbnailURL(assetID: String) -> URL? {
        let url = cacheDirectory.appendingPathComponent("thumb_\(assetID).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Calculate total cache size
    func currentCacheSize() throws -> Int64 {
        let contents = try FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return try contents.reduce(0) { total, url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            return total + Int64(values.fileSize ?? 0)
        }
    }

    /// Evict oldest cached files when over size limit (LRU)
    func evictIfNeeded() throws {
        let currentSize = try currentCacheSize()
        guard currentSize > maxCacheSize else { return }

        let contents = try FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentAccessDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        let sorted = try contents.sorted { a, b in
            let dateA = try a.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate ?? .distantPast
            let dateB = try b.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate ?? .distantPast
            return dateA < dateB
        }

        var freed: Int64 = 0
        let target = currentSize - (maxCacheSize / 2) // Free to 50% capacity

        for url in sorted {
            guard freed < target else { break }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            try FileManager.default.removeItem(at: url)
            freed += Int64(size)
        }

        logger.info("Evicted \(freed / 1024 / 1024)MB from cache")
    }

    /// Clear all cached files
    func clearAll() throws {
        try FileManager.default.removeItem(at: cacheDirectory)
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        logger.info("Cache cleared")
    }
}
