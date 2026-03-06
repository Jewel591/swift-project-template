# Talon v1.0 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a free, read-only Eagle library companion app for iPhone (iPad adaptive) with browse, search, and preview capabilities.

**Architecture:** MVVM + GRDB (SQLite + FTS5). Three-layer Eagle parsing (FileSystem -> DTO -> GRDB Record). Actor-based thumbnail loading. iCloud Drive + SMB file access via security-scoped bookmarks.

**Tech Stack:** SwiftUI, GRDB, GRDBQuery, Swift Concurrency (async/await + Actor), ImageIO, PDFKit, WKWebView

---

## Phase 1: Foundation (GRDB Models + Eagle Parser + File Access)

### Task 1: Add GRDB Package Dependency

**Files:**
- Modify: `Talon.xcodeproj/project.pbxproj`

**Step 1: Add GRDB and GRDBQuery SPM packages**

Open the Xcode project and add these Swift Package dependencies:
- `GRDB` — `https://github.com/groue/GRDB.swift.git` (version 7.0.0+)
- `GRDBQuery` — `https://github.com/groue/GRDBQuery.git` (version 0.9.0+)

Since we cannot modify `.pbxproj` reliably via CLI, use `xcodebuild` or add via Xcode GUI.

Alternatively, create a `Package.swift` for local package management or add directly to the project.

**Step 2: Verify build**

Run: `xcodebuild -project Talon.xcodeproj -scheme Talon -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add -A && git commit -m "chore: add GRDB and GRDBQuery package dependencies"
```

---

### Task 2: Create GRDB Record Models — Asset

**Files:**
- Create: `Talon/Models/Asset.swift`
- Create: `Talon/Models/AssetTag.swift`
- Create: `Talon/Models/AssetFolder.swift`

**Step 1: Write Asset record**

```swift
// Talon/Models/Asset.swift
import Foundation
import GRDB

struct Asset: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: String              // Eagle 13-digit random ID
    var name: String
    var fileExtension: String
    var fileSize: Int64
    var width: Int
    var height: Int
    var rating: Int
    var sourceURL: String?
    var annotation: String?
    var createdAt: Date
    var modifiedAt: Date
    var importedAt: Date
    var relativePath: String
    var thumbnailPath: String
    var primaryColorHex: String?
    var palettesJSON: String?
    var thumbnailCached: Bool
    var originalCached: Bool
    var lastAccessedAt: Date?

    // GRDB associations
    static let assetTags = hasMany(AssetTag.self)
    static let assetFolders = hasMany(AssetFolder.self)
}
```

**Step 2: Write AssetTag record**

```swift
// Talon/Models/AssetTag.swift
import Foundation
import GRDB

struct AssetTag: Codable, FetchableRecord, PersistableRecord {
    var assetID: String
    var tag: String

    static let asset = belongsTo(Asset.self)
}
```

**Step 3: Write AssetFolder record**

```swift
// Talon/Models/AssetFolder.swift
import Foundation
import GRDB

struct AssetFolder: Codable, FetchableRecord, PersistableRecord {
    var assetID: String
    var folderID: String

    static let asset = belongsTo(Asset.self)
    static let folder = belongsTo(Folder.self)
}
```

**Step 4: Commit**

```bash
git add Talon/Models/Asset.swift Talon/Models/AssetTag.swift Talon/Models/AssetFolder.swift
git commit -m "feat: add GRDB record models for Asset, AssetTag, AssetFolder"
```

---

### Task 3: Create GRDB Record Models — Folder & Tag

**Files:**
- Create: `Talon/Models/Folder.swift`
- Create: `Talon/Models/Tag.swift`

**Step 1: Write Folder record**

```swift
// Talon/Models/Folder.swift
import Foundation
import GRDB

struct Folder: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: String
    var name: String
    var parentID: String?

    // Self-referencing tree
    static let parent = belongsTo(Folder.self, key: "parent", using: ForeignKey(["parentID"]))
    static let children = hasMany(Folder.self, key: "children", using: ForeignKey(["parentID"]))
    static let assetFolders = hasMany(AssetFolder.self)
}
```

**Step 2: Write Tag record**

```swift
// Talon/Models/Tag.swift
import Foundation
import GRDB

struct Tag: Codable, FetchableRecord, PersistableRecord {
    var name: String
    var color: String?

    // Use name as primary key
    static let databaseTableName = "tag"
}

extension Tag {
    enum Columns {
        static let name = Column(CodingKeys.name)
        static let color = Column(CodingKeys.color)
    }
}
```

**Step 3: Commit**

```bash
git add Talon/Models/Folder.swift Talon/Models/Tag.swift
git commit -m "feat: add GRDB record models for Folder and Tag"
```

---

### Task 4: Create AppDatabase — Migration & Configuration

**Files:**
- Create: `Talon/Models/AppDatabase.swift`

**Step 1: Write AppDatabase with migrations**

```swift
// Talon/Models/AppDatabase.swift
import Foundation
import GRDB

struct AppDatabase {
    let dbWriter: any DatabaseWriter

    init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1-createTables") { db in
            // Asset
            try db.create(table: "asset") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("fileExtension", .text).notNull()
                t.column("fileSize", .integer).notNull()
                t.column("width", .integer).notNull()
                t.column("height", .integer).notNull()
                t.column("rating", .integer).notNull().defaults(to: 0)
                t.column("sourceURL", .text)
                t.column("annotation", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("modifiedAt", .datetime).notNull()
                t.column("importedAt", .datetime).notNull()
                t.column("relativePath", .text).notNull()
                t.column("thumbnailPath", .text).notNull()
                t.column("primaryColorHex", .text)
                t.column("palettesJSON", .text)
                t.column("thumbnailCached", .boolean).notNull().defaults(to: false)
                t.column("originalCached", .boolean).notNull().defaults(to: false)
                t.column("lastAccessedAt", .datetime)
            }

            // Folder (self-referencing tree)
            try db.create(table: "folder") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("parentID", .text).references("folder", onDelete: .cascade)
            }

            // Tag
            try db.create(table: "tag") { t in
                t.primaryKey("name", .text)
                t.column("color", .text)
            }

            // AssetTag (many-to-many)
            try db.create(table: "assetTag") { t in
                t.column("assetID", .text).notNull().references("asset", onDelete: .cascade)
                t.column("tag", .text).notNull()
                t.primaryKey(["assetID", "tag"])
            }

            // AssetFolder (many-to-many)
            try db.create(table: "assetFolder") { t in
                t.column("assetID", .text).notNull().references("asset", onDelete: .cascade)
                t.column("folderID", .text).notNull().references("folder", onDelete: .cascade)
                t.primaryKey(["assetID", "folderID"])
            }
        }

        migrator.registerMigration("v1-createIndexes") { db in
            try db.create(index: "idx_asset_importedAt", on: "asset", columns: ["importedAt"])
            try db.create(index: "idx_asset_rating", on: "asset", columns: ["rating"])
            try db.create(index: "idx_asset_ext", on: "asset", columns: ["fileExtension"])
            try db.create(index: "idx_asset_color", on: "asset", columns: ["primaryColorHex"])
            try db.create(index: "idx_asset_lastAccess", on: "asset", columns: ["lastAccessedAt"])
            try db.create(index: "idx_asset_tag_tag", on: "assetTag", columns: ["tag", "assetID"])
            try db.create(index: "idx_asset_folder", on: "assetFolder", columns: ["folderID", "assetID"])
            try db.create(index: "idx_asset_ext_time", on: "asset", columns: ["fileExtension", "importedAt"])
            try db.create(index: "idx_asset_rating_time", on: "asset", columns: ["rating", "importedAt"])
        }

        migrator.registerMigration("v1-createFTS5") { db in
            try db.create(virtualTable: "assetFTS", using: FTS5()) { t in
                t.column("name")
                t.column("tags")
                t.column("annotation")
            }
        }

        return migrator
    }
}

extension AppDatabase {
    /// Create an in-memory database for previews and testing
    static func empty() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    /// Create a database at the given path for a specific Eagle library
    static func openLibrary(at path: String) throws -> AppDatabase {
        let dbQueue = try DatabaseQueue(path: path)
        return try AppDatabase(dbQueue)
    }
}
```

**Step 2: Commit**

```bash
git add Talon/Models/AppDatabase.swift
git commit -m "feat: add AppDatabase with GRDB migrations, indexes, and FTS5"
```

---

### Task 5: Create Eagle DTO Models

**Files:**
- Create: `Talon/DTOs/AssetDTO.swift`
- Create: `Talon/DTOs/TagDTO.swift`
- Create: `Talon/DTOs/LibraryDTO.swift`

**Step 1: Write AssetDTO**

```swift
// Talon/DTOs/AssetDTO.swift
import Foundation

/// Maps 1:1 to Eagle's per-asset metadata.json
struct AssetDTO: Codable {
    let id: String
    let name: String
    let size: Int64
    let ext: String
    let width: Int
    let height: Int
    let tags: [String]?
    let folders: [String]?
    let url: String?
    let annotation: String?
    let star: Int?
    let modificationTime: Int64
    let lastModified: Int64
    let palettes: [[PaletteDTO]]?

    struct PaletteDTO: Codable {
        let color: [Int]
        let ratio: Double
    }
}

extension AssetDTO {
    /// Convert Eagle millisecond timestamp to Date
    func toAsset(relativePath: String, thumbnailPath: String) -> Asset {
        Asset(
            id: id,
            name: name,
            fileExtension: ext,
            fileSize: size,
            width: width,
            height: height,
            rating: star ?? 0,
            sourceURL: url,
            annotation: annotation,
            createdAt: Date(timeIntervalSince1970: Double(modificationTime) / 1000.0),
            modifiedAt: Date(timeIntervalSince1970: Double(lastModified) / 1000.0),
            importedAt: Date(timeIntervalSince1970: Double(modificationTime) / 1000.0),
            relativePath: relativePath,
            thumbnailPath: thumbnailPath,
            primaryColorHex: primaryColorHex,
            palettesJSON: palettesJSONString,
            thumbnailCached: false,
            originalCached: false,
            lastAccessedAt: nil
        )
    }

    private var primaryColorHex: String? {
        guard let palettes = palettes, let first = palettes.first?.first else { return nil }
        let rgb = first.color
        guard rgb.count >= 3 else { return nil }
        return String(format: "#%02X%02X%02X", rgb[0], rgb[1], rgb[2])
    }

    private var palettesJSONString: String? {
        guard let palettes = palettes else { return nil }
        guard let data = try? JSONEncoder().encode(palettes) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

**Step 2: Write TagDTO**

```swift
// Talon/DTOs/TagDTO.swift
import Foundation

/// Maps to Eagle's tags.json entries
struct TagDTO: Codable {
    let id: String
    let name: String
    let color: String?
}

extension TagDTO {
    func toTag() -> Tag {
        Tag(name: name, color: color)
    }
}
```

**Step 3: Write LibraryDTO**

```swift
// Talon/DTOs/LibraryDTO.swift
import Foundation

/// Maps to Eagle's root metadata.json
struct LibraryDTO: Codable {
    let folders: [FolderDTO]?
    let modificationTime: Int64?
    let applicationVersion: String?
}

struct FolderDTO: Codable {
    let id: String
    let name: String
    let children: [FolderDTO]?
}

extension FolderDTO {
    /// Flatten nested folder tree into Folder records
    func toFolders(parentID: String? = nil) -> [Folder] {
        var result = [Folder(id: id, name: name, parentID: parentID)]
        if let children = children {
            for child in children {
                result.append(contentsOf: child.toFolders(parentID: id))
            }
        }
        return result
    }
}
```

**Step 4: Commit**

```bash
git add Talon/DTOs/
git commit -m "feat: add Eagle DTO models (AssetDTO, TagDTO, LibraryDTO)"
```

---

### Task 6: Create EagleLibraryScanner

**Files:**
- Create: `Talon/Services/EagleLibraryScanner.swift`

**Step 1: Write scanner service**

```swift
// Talon/Services/EagleLibraryScanner.swift
import Foundation

/// Scans Eagle .library directory structure and discovers asset folders
struct EagleLibraryScanner {

    /// Scan the images/ directory and return paths to all asset info folders
    func scanAssetFolders(libraryURL: URL) throws -> [URL] {
        let imagesURL = libraryURL.appendingPathComponent("images")
        let contents = try FileManager.default.contentsOfDirectory(
            at: imagesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return contents.filter { url in
            url.pathExtension == "info" && url.hasDirectoryPath
        }
    }

    /// Find asset folders modified after a given date (for incremental scan)
    func scanModifiedAssetFolders(libraryURL: URL, since date: Date) throws -> [URL] {
        let allFolders = try scanAssetFolders(libraryURL: libraryURL)
        return try allFolders.filter { url in
            let metadataURL = url.appendingPathComponent("metadata.json")
            let attributes = try FileManager.default.attributesOfItem(atPath: metadataURL.path)
            guard let modDate = attributes[.modificationDate] as? Date else { return true }
            return modDate > date
        }
    }

    /// Read the root metadata.json
    func readLibraryMetadata(libraryURL: URL) throws -> LibraryDTO {
        let url = libraryURL.appendingPathComponent("metadata.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LibraryDTO.self, from: data)
    }

    /// Read tags.json
    func readTags(libraryURL: URL) throws -> [TagDTO] {
        let url = libraryURL.appendingPathComponent("tags.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([TagDTO].self, from: data)
    }
}
```

**Step 2: Commit**

```bash
git add Talon/Services/EagleLibraryScanner.swift
git commit -m "feat: add EagleLibraryScanner for .library directory traversal"
```

---

### Task 7: Create EagleMetadataParser

**Files:**
- Create: `Talon/Services/EagleMetadataParser.swift`

**Step 1: Write parser service**

```swift
// Talon/Services/EagleMetadataParser.swift
import Foundation

/// Parses individual asset metadata.json files into DTOs
struct EagleMetadataParser {

    /// Parse a single asset's metadata.json
    func parseAsset(at folderURL: URL) throws -> AssetDTO {
        let metadataURL = folderURL.appendingPathComponent("metadata.json")
        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode(AssetDTO.self, from: data)
    }

    /// Parse multiple asset folders concurrently
    func parseAssets(folders: [URL], maxConcurrency: Int = 8) async throws -> [(URL, AssetDTO)] {
        try await withThrowingTaskGroup(of: (URL, AssetDTO)?.self) { group in
            var results: [(URL, AssetDTO)] = []
            var pending = folders.makeIterator()
            var activeCount = 0

            // Seed initial tasks
            for _ in 0..<min(maxConcurrency, folders.count) {
                if let folder = pending.next() {
                    activeCount += 1
                    group.addTask {
                        do {
                            let dto = try parseAsset(at: folder)
                            return (folder, dto)
                        } catch {
                            return nil // Skip unparseable assets
                        }
                    }
                }
            }

            for try await result in group {
                activeCount -= 1
                if let result {
                    results.append(result)
                }
                // Add next task
                if let folder = pending.next() {
                    activeCount += 1
                    group.addTask {
                        do {
                            let dto = try self.parseAsset(at: folder)
                            return (folder, dto)
                        } catch {
                            return nil
                        }
                    }
                }
            }

            return results
        }
    }
}
```

**Step 2: Commit**

```bash
git add Talon/Services/EagleMetadataParser.swift
git commit -m "feat: add EagleMetadataParser with concurrent JSON parsing"
```

---

### Task 8: Create LibraryIndexer

**Files:**
- Create: `Talon/Services/LibraryIndexer.swift`

**Step 1: Write indexer service**

```swift
// Talon/Services/LibraryIndexer.swift
import Foundation
import GRDB

/// Converts parsed DTOs into GRDB records via batch SQL transactions
struct LibraryIndexer {
    let database: AppDatabase

    /// Full import: parse all assets and write to database
    func indexLibrary(libraryURL: URL, progress: @escaping (Int, Int) -> Void) async throws {
        let scanner = EagleLibraryScanner()
        let parser = EagleMetadataParser()

        // 1. Parse library metadata (folders)
        let libraryMeta = try scanner.readLibraryMetadata(libraryURL: libraryURL)
        let folders = libraryMeta.folders?.flatMap { $0.toFolders() } ?? []

        // 2. Parse tags
        let tagDTOs = try scanner.readTags(libraryURL: libraryURL)
        let tags = tagDTOs.map { $0.toTag() }

        // 3. Scan and parse all assets
        let assetFolders = try scanner.scanAssetFolders(libraryURL: libraryURL)
        let totalCount = assetFolders.count
        let parsed = try await parser.parseAssets(folders: assetFolders)

        // 4. Batch write to database
        try await database.dbWriter.write { db in
            // Insert folders
            for folder in folders {
                try folder.insert(db, onConflict: .replace)
            }

            // Insert tags
            for tag in tags {
                try tag.insert(db, onConflict: .replace)
            }

            // Insert assets in batches
            for (index, (folderURL, dto)) in parsed.enumerated() {
                let relativePath = folderURL.lastPathComponent
                let thumbnailPath = folderURL
                    .appendingPathComponent("_thumbnail.png").lastPathComponent

                let asset = dto.toAsset(
                    relativePath: relativePath,
                    thumbnailPath: "\(relativePath)/_thumbnail.png"
                )
                try asset.insert(db, onConflict: .replace)

                // Insert asset-tag associations
                if let tags = dto.tags {
                    for tag in tags {
                        try AssetTag(assetID: dto.id, tag: tag)
                            .insert(db, onConflict: .ignore)
                    }
                }

                // Insert asset-folder associations
                if let folderIDs = dto.folders {
                    for folderID in folderIDs {
                        try AssetFolder(assetID: dto.id, folderID: folderID)
                            .insert(db, onConflict: .ignore)
                    }
                }

                if (index + 1) % 100 == 0 {
                    progress(index + 1, totalCount)
                }
            }

            // Build FTS5 index
            try db.execute(sql: """
                INSERT INTO assetFTS(rowid, name, tags, annotation)
                SELECT rowid, name,
                       (SELECT GROUP_CONCAT(tag, ' ') FROM assetTag WHERE assetID = asset.id),
                       annotation
                FROM asset
            """)
        }

        progress(totalCount, totalCount)
    }
}
```

**Step 2: Commit**

```bash
git add Talon/Services/LibraryIndexer.swift
git commit -m "feat: add LibraryIndexer for batch GRDB import with FTS5"
```

---

### Task 9: Create ScopedAccessManager

**Files:**
- Create: `Talon/Services/ScopedAccessManager.swift`

**Step 1: Write scoped access manager**

```swift
// Talon/Services/ScopedAccessManager.swift
import Foundation

/// Manages security-scoped bookmarks for persistent file access
actor ScopedAccessManager {
    private let bookmarksKey = "com.talon.securityBookmarks"

    /// Save a security-scoped bookmark for a URL
    func saveBookmark(for url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        var bookmarks = loadBookmarkStore()
        bookmarks[url.path] = bookmarkData
        UserDefaults.standard.set(
            try JSONEncoder().encode(bookmarks),
            forKey: bookmarksKey
        )
    }

    /// Resolve a previously saved bookmark
    func resolveBookmark(for path: String) throws -> URL? {
        let bookmarks = loadBookmarkStore()
        guard let data = bookmarks[path] else { return nil }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            // Re-save the bookmark
            try saveBookmark(for: url)
        }
        return url
    }

    /// Execute a closure with scoped access to a URL
    func withAccess<T>(to url: URL, perform work: (URL) throws -> T) throws -> T {
        guard url.startAccessingSecurityScopedResource() else {
            throw ScopedAccessError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return try work(url)
    }

    /// List all saved library paths
    func savedLibraryPaths() -> [String] {
        Array(loadBookmarkStore().keys)
    }

    /// Remove a saved bookmark
    func removeBookmark(for path: String) {
        var bookmarks = loadBookmarkStore()
        bookmarks.removeValue(forKey: path)
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        }
    }

    private func loadBookmarkStore() -> [String: Data] {
        guard let data = UserDefaults.standard.data(forKey: bookmarksKey),
              let store = try? JSONDecoder().decode([String: Data].self, from: data)
        else { return [:] }
        return store
    }
}

enum ScopedAccessError: Error {
    case accessDenied
    case bookmarkStale
}
```

**Step 2: Commit**

```bash
git add Talon/Services/ScopedAccessManager.swift
git commit -m "feat: add ScopedAccessManager for security-scoped bookmarks"
```

---

## Phase 2: Browse (UI + Layouts + Thumbnails)

### Task 10: Create ThumbnailLoader Actor

**Files:**
- Create: `Talon/Services/ThumbnailLoader.swift`

**Step 1: Write thumbnail loader**

```swift
// Talon/Services/ThumbnailLoader.swift
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
```

**Step 2: Commit**

```bash
git add Talon/Services/ThumbnailLoader.swift
git commit -m "feat: add ThumbnailLoader actor with ImageIO decoding and request merging"
```

---

### Task 11: Create ThumbnailView Component

**Files:**
- Create: `Talon/Components/ThumbnailView.swift`

**Step 1: Write thumbnail SwiftUI view**

```swift
// Talon/Components/ThumbnailView.swift
import SwiftUI

struct ThumbnailView: View {
    let assetID: String
    let thumbnailURL: URL
    let aspectRatio: CGFloat

    @State private var image: UIImage?
    @Environment(\.thumbnailLoader) private var loader

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.Background.card)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .task(id: assetID) {
            image = await loader.loadThumbnail(
                assetID: assetID,
                thumbnailURL: thumbnailURL,
                targetSize: CGSize(width: 200, height: 200)
            )
        }
    }
}

// Environment key for ThumbnailLoader
private struct ThumbnailLoaderKey: EnvironmentKey {
    static let defaultValue = ThumbnailLoader()
}

extension EnvironmentValues {
    var thumbnailLoader: ThumbnailLoader {
        get { self[ThumbnailLoaderKey.self] }
        set { self[ThumbnailLoaderKey.self] = newValue }
    }
}
```

**Step 2: Commit**

```bash
git add Talon/Components/ThumbnailView.swift
git commit -m "feat: add ThumbnailView with async loading and environment injection"
```

---

### Task 12: Create AssetGridViewModel

**Files:**
- Create: `Talon/Features/AssetGrid/AssetGridViewModel.swift`

**Step 1: Write ViewModel**

```swift
// Talon/Features/AssetGrid/AssetGridViewModel.swift
import Foundation
import GRDB
import Observation

enum LayoutMode: String, CaseIterable {
    case waterfall
    case grid
    case list
}

enum SortField: String, CaseIterable {
    case importedAt
    case modifiedAt
    case name
    case fileSize
    case rating
}

@Observable
@MainActor
final class AssetGridViewModel {
    private(set) var assets: [Asset] = []
    private(set) var isLoading = false
    private(set) var totalCount = 0
    var layoutMode: LayoutMode = .grid
    var sortField: SortField = .importedAt
    var sortAscending = false

    private var observation: AnyDatabaseCancellable?
    private let pageSize = 50
    private var currentPage = 0

    func observe(database: AppDatabase, folderID: String? = nil) {
        observation = ValueObservation
            .tracking { [sortField, sortAscending, pageSize, folderID] db -> [Asset] in
                var query = Asset.all()
                if let folderID {
                    query = query
                        .joining(required: Asset.assetFolders.filter(Column("folderID") == folderID))
                }
                let ordering: SQLOrderingTerm = sortAscending
                    ? Column(sortField.rawValue).asc
                    : Column(sortField.rawValue).desc
                return try query
                    .order(ordering)
                    .limit(pageSize)
                    .fetchAll(db)
            }
            .start(in: database.dbWriter, onError: { _ in }, onChange: { [weak self] assets in
                self?.assets = assets
            })
    }

    func loadNextPage(database: AppDatabase) async {
        guard !isLoading else { return }
        isLoading = true
        currentPage += 1
        let offset = currentPage * pageSize
        do {
            let moreAssets = try await database.dbWriter.read { [sortField, sortAscending, pageSize] db in
                let ordering: SQLOrderingTerm = sortAscending
                    ? Column(sortField.rawValue).asc
                    : Column(sortField.rawValue).desc
                return try Asset.all()
                    .order(ordering)
                    .limit(pageSize, offset: offset)
                    .fetchAll(db)
            }
            assets.append(contentsOf: moreAssets)
        } catch {}
        isLoading = false
    }
}
```

**Step 2: Commit**

```bash
git add Talon/Features/AssetGrid/AssetGridViewModel.swift
git commit -m "feat: add AssetGridViewModel with pagination and sorting"
```

---

### Task 13: Create Grid and List Layout Views

**Files:**
- Create: `Talon/Features/AssetGrid/AssetGridView.swift`

**Step 1: Write grid view with layout switching**

```swift
// Talon/Features/AssetGrid/AssetGridView.swift
import SwiftUI

struct AssetGridView: View {
    @Bindable var viewModel: AssetGridViewModel
    let libraryURL: URL
    let onAssetTap: (Asset) -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 100), spacing: BrandSpacing.compact)
    ]

    var body: some View {
        Group {
            switch viewModel.layoutMode {
            case .grid:
                gridLayout
            case .waterfall:
                waterfallLayout
            case .list:
                listLayout
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                layoutPicker
            }
        }
    }

    private var gridLayout: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: BrandSpacing.compact) {
                ForEach(viewModel.assets) { asset in
                    assetThumbnail(asset)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                        .onTapGesture { onAssetTap(asset) }
                }
            }
            .padding(.horizontal, BrandSpacing.pageHorizontal)
        }
    }

    private var waterfallLayout: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: BrandSpacing.compact)],
                spacing: BrandSpacing.compact
            ) {
                ForEach(viewModel.assets) { asset in
                    assetThumbnail(asset)
                        .aspectRatio(
                            CGFloat(asset.width) / max(CGFloat(asset.height), 1),
                            contentMode: .fit
                        )
                        .onTapGesture { onAssetTap(asset) }
                }
            }
            .padding(.horizontal, BrandSpacing.pageHorizontal)
        }
    }

    private var listLayout: some View {
        List(viewModel.assets) { asset in
            HStack(spacing: BrandSpacing.cardContent) {
                assetThumbnail(asset)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.name)
                        .font(.body)
                        .foregroundStyle(Color.Text.primary)
                        .lineLimit(1)
                    Text("\(asset.fileExtension.uppercased()) · \(formatFileSize(asset.fileSize))")
                        .font(.caption)
                        .foregroundStyle(Color.Text.secondary)
                }
            }
            .onTapGesture { onAssetTap(asset) }
        }
        .listStyle(.plain)
    }

    private func assetThumbnail(_ asset: Asset) -> some View {
        let url = libraryURL
            .appendingPathComponent("images")
            .appendingPathComponent(asset.relativePath)
            .appendingPathComponent("_thumbnail.png")
        return ThumbnailView(
            assetID: asset.id,
            thumbnailURL: url,
            aspectRatio: CGFloat(asset.width) / max(CGFloat(asset.height), 1)
        )
    }

    private var layoutPicker: some View {
        Menu {
            ForEach(LayoutMode.allCases, id: \.self) { mode in
                Button {
                    viewModel.layoutMode = mode
                } label: {
                    Label(mode.rawValue.capitalized, systemImage: layoutIcon(mode))
                }
            }
        } label: {
            Image(systemName: layoutIcon(viewModel.layoutMode))
        }
    }

    private func layoutIcon(_ mode: LayoutMode) -> String {
        switch mode {
        case .grid: "square.grid.2x2"
        case .waterfall: "rectangle.grid.1x2"
        case .list: "list.bullet"
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
```

**Step 2: Commit**

```bash
git add Talon/Features/AssetGrid/AssetGridView.swift
git commit -m "feat: add AssetGridView with grid, waterfall, and list layouts"
```

---

### Task 14: Create Folder Navigation View

**Files:**
- Create: `Talon/Features/LibraryBrowser/LibraryBrowserView.swift`
- Create: `Talon/Features/LibraryBrowser/LibraryBrowserViewModel.swift`

**Step 1: Write LibraryBrowserViewModel**

```swift
// Talon/Features/LibraryBrowser/LibraryBrowserViewModel.swift
import Foundation
import GRDB
import Observation

@Observable
@MainActor
final class LibraryBrowserViewModel {
    private(set) var rootFolders: [Folder] = []
    private(set) var currentFolder: Folder?
    private(set) var breadcrumbs: [Folder] = []
    private(set) var childFolders: [Folder] = []
    private(set) var isIndexing = false
    private(set) var indexingProgress: (current: Int, total: Int) = (0, 0)

    var database: AppDatabase?
    var libraryURL: URL?

    func loadRootFolders() async {
        guard let database else { return }
        do {
            rootFolders = try await database.dbWriter.read { db in
                try Folder.filter(Column("parentID") == nil).fetchAll(db)
            }
        } catch {}
    }

    func navigateToFolder(_ folder: Folder) async {
        currentFolder = folder
        breadcrumbs.append(folder)
        guard let database else { return }
        do {
            childFolders = try await database.dbWriter.read { db in
                try Folder.filter(Column("parentID") == folder.id).fetchAll(db)
            }
        } catch {}
    }

    func navigateBack() async {
        breadcrumbs.removeLast()
        currentFolder = breadcrumbs.last
        if let current = currentFolder {
            await navigateToFolder(current)
            // Remove duplicate from breadcrumbs since navigateToFolder appends
            if breadcrumbs.count > 1 {
                breadcrumbs.removeLast()
            }
        } else {
            childFolders = []
            await loadRootFolders()
        }
    }

    func indexLibrary() async {
        guard let database, let libraryURL else { return }
        isIndexing = true
        let indexer = LibraryIndexer(database: database)
        do {
            try await indexer.indexLibrary(libraryURL: libraryURL) { current, total in
                Task { @MainActor in
                    self.indexingProgress = (current, total)
                }
            }
        } catch {}
        isIndexing = false
        await loadRootFolders()
    }
}
```

**Step 2: Write LibraryBrowserView**

```swift
// Talon/Features/LibraryBrowser/LibraryBrowserView.swift
import SwiftUI

struct LibraryBrowserView: View {
    @State private var browserVM = LibraryBrowserViewModel()
    @State private var gridVM = AssetGridViewModel()
    @State private var selectedAsset: Asset?
    let database: AppDatabase
    let libraryURL: URL

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !browserVM.breadcrumbs.isEmpty {
                    breadcrumbBar
                }
                if !folderList.isEmpty {
                    folderSection
                }
                AssetGridView(
                    viewModel: gridVM,
                    libraryURL: libraryURL,
                    onAssetTap: { selectedAsset = $0 }
                )
            }
            .navigationTitle(browserVM.currentFolder?.name ?? "Library")
            .task {
                browserVM.database = database
                browserVM.libraryURL = libraryURL
                gridVM.observe(database: database, folderID: browserVM.currentFolder?.id)
                await browserVM.loadRootFolders()
            }
            .overlay {
                if browserVM.isIndexing {
                    indexingOverlay
                }
            }
        }
    }

    private var folderList: [Folder] {
        browserVM.currentFolder == nil ? browserVM.rootFolders : browserVM.childFolders
    }

    private var folderSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.compact) {
                ForEach(folderList) { folder in
                    Button {
                        Task {
                            await browserVM.navigateToFolder(folder)
                            gridVM.observe(database: database, folderID: folder.id)
                        }
                    } label: {
                        Label(folder.name, systemImage: "folder")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.Background.card)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.pageHorizontal)
            .padding(.vertical, BrandSpacing.compact)
        }
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button("Root") {
                    Task {
                        browserVM.breadcrumbs = []
                        browserVM.currentFolder = nil
                        gridVM.observe(database: database)
                        await browserVM.loadRootFolders()
                    }
                }
                ForEach(browserVM.breadcrumbs) { folder in
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.Text.tertiary)
                    Button(folder.name) {
                        // Navigate to this breadcrumb level
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(Color.Text.secondary)
            .padding(.horizontal, BrandSpacing.pageHorizontal)
            .padding(.vertical, 4)
        }
    }

    private var indexingOverlay: some View {
        VStack(spacing: BrandSpacing.cardContent) {
            ProgressView(
                value: Double(browserVM.indexingProgress.current),
                total: Double(max(browserVM.indexingProgress.total, 1))
            )
            Text("Indexing \(browserVM.indexingProgress.current)/\(browserVM.indexingProgress.total)")
                .font(.caption)
                .foregroundStyle(Color.Text.secondary)
        }
        .padding(BrandSpacing.cardPadding)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
```

**Step 3: Commit**

```bash
git add Talon/Features/LibraryBrowser/
git commit -m "feat: add LibraryBrowserView with folder navigation and breadcrumbs"
```

---

## Phase 3: Search (FTS5 + Multi-dimensional Filtering)

### Task 15: Create SearchCoordinator

**Files:**
- Create: `Talon/Features/Search/SearchCoordinator.swift`

**Step 1: Write search coordinator**

```swift
// Talon/Features/Search/SearchCoordinator.swift
import Foundation
import GRDB

struct SearchQuery {
    var keyword: String?
    var tags: [String]?
    var fileTypes: [String]?
    var ratingMin: Int?
    var dateFrom: Date?
    var dateTo: Date?
    var folderID: String?
    var sortField: SortField = .importedAt
    var sortAscending: Bool = false
}

struct SearchCoordinator {
    let database: AppDatabase

    func search(_ query: SearchQuery, limit: Int = 50, offset: Int = 0) async throws -> [Asset] {
        try await database.dbWriter.read { db in
            var sql = "SELECT DISTINCT asset.* FROM asset"
            var arguments: [any DatabaseValueConvertible] = []
            var joins: [String] = []
            var conditions: [String] = []

            // FTS5 keyword search
            if let keyword = query.keyword, !keyword.isEmpty {
                joins.append("JOIN assetFTS ON asset.rowid = assetFTS.rowid")
                conditions.append("assetFTS MATCH ?")
                // Append wildcard for prefix matching
                arguments.append("\(keyword)*")
            }

            // Tag filter
            if let tags = query.tags, !tags.isEmpty {
                joins.append("JOIN assetTag ON assetTag.assetID = asset.id")
                let placeholders = tags.map { _ in "?" }.joined(separator: ", ")
                conditions.append("assetTag.tag IN (\(placeholders))")
                arguments.append(contentsOf: tags)
            }

            // File type filter
            if let fileTypes = query.fileTypes, !fileTypes.isEmpty {
                let placeholders = fileTypes.map { _ in "?" }.joined(separator: ", ")
                conditions.append("asset.fileExtension IN (\(placeholders))")
                arguments.append(contentsOf: fileTypes)
            }

            // Rating filter
            if let ratingMin = query.ratingMin, ratingMin > 0 {
                conditions.append("asset.rating >= ?")
                arguments.append(ratingMin)
            }

            // Date range filter
            if let dateFrom = query.dateFrom {
                conditions.append("asset.importedAt >= ?")
                arguments.append(dateFrom)
            }
            if let dateTo = query.dateTo {
                conditions.append("asset.importedAt <= ?")
                arguments.append(dateTo)
            }

            // Folder filter
            if let folderID = query.folderID {
                joins.append("JOIN assetFolder ON assetFolder.assetID = asset.id")
                conditions.append("assetFolder.folderID = ?")
                arguments.append(folderID)
            }

            // Build final SQL
            sql += " " + joins.joined(separator: " ")
            if !conditions.isEmpty {
                sql += " WHERE " + conditions.joined(separator: " AND ")
            }

            let direction = query.sortAscending ? "ASC" : "DESC"
            sql += " ORDER BY asset.\(query.sortField.rawValue) \(direction)"
            sql += " LIMIT ? OFFSET ?"
            arguments.append(limit)
            arguments.append(offset)

            return try Asset.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }
}
```

**Step 2: Commit**

```bash
git add Talon/Features/Search/SearchCoordinator.swift
git commit -m "feat: add SearchCoordinator with FTS5 and multi-dimensional filtering"
```

---

### Task 16: Create SearchView and SearchViewModel

**Files:**
- Create: `Talon/Features/Search/SearchViewModel.swift`
- Create: `Talon/Features/Search/SearchView.swift`

**Step 1: Write SearchViewModel**

```swift
// Talon/Features/Search/SearchViewModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class SearchViewModel {
    var searchText = ""
    private(set) var results: [Asset] = []
    private(set) var isSearching = false
    private(set) var searchHistory: [String] = []

    // Filter state
    var selectedTags: [String] = []
    var selectedFileTypes: [String] = []
    var minRating: Int = 0
    var dateFrom: Date?
    var dateTo: Date?

    private var searchTask: Task<Void, Never>?
    private let historyKey = "com.talon.searchHistory"

    init() {
        searchHistory = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }

    func performSearch(coordinator: SearchCoordinator) {
        searchTask?.cancel()
        searchTask = Task {
            // Debounce 300ms
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            isSearching = true
            let query = SearchQuery(
                keyword: searchText.isEmpty ? nil : searchText,
                tags: selectedTags.isEmpty ? nil : selectedTags,
                fileTypes: selectedFileTypes.isEmpty ? nil : selectedFileTypes,
                ratingMin: minRating > 0 ? minRating : nil,
                dateFrom: dateFrom,
                dateTo: dateTo
            )
            do {
                results = try await coordinator.search(query)
            } catch {}
            isSearching = false

            // Save to history
            if !searchText.isEmpty {
                saveToHistory(searchText)
            }
        }
    }

    func clearFilters() {
        selectedTags = []
        selectedFileTypes = []
        minRating = 0
        dateFrom = nil
        dateTo = nil
    }

    private func saveToHistory(_ text: String) {
        searchHistory.removeAll { $0 == text }
        searchHistory.insert(text, at: 0)
        if searchHistory.count > 50 { searchHistory = Array(searchHistory.prefix(50)) }
        UserDefaults.standard.set(searchHistory, forKey: historyKey)
    }
}
```

**Step 2: Write SearchView**

```swift
// Talon/Features/Search/SearchView.swift
import SwiftUI

struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    let database: AppDatabase
    let libraryURL: URL

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.results.isEmpty && viewModel.searchText.isEmpty {
                    historySection
                } else {
                    AssetGridView(
                        viewModel: AssetGridViewModel(),
                        libraryURL: libraryURL,
                        onAssetTap: { _ in }
                    )
                }
            }
            .navigationTitle("Search")
            .searchable(text: $viewModel.searchText, prompt: "Search assets...")
            .onChange(of: viewModel.searchText) {
                let coordinator = SearchCoordinator(database: database)
                viewModel.performSearch(coordinator: coordinator)
            }
        }
    }

    private var historySection: some View {
        List {
            if !viewModel.searchHistory.isEmpty {
                Section("Recent") {
                    ForEach(viewModel.searchHistory, id: \.self) { query in
                        Button {
                            viewModel.searchText = query
                        } label: {
                            Label(query, systemImage: "clock")
                                .foregroundStyle(Color.Text.primary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}
```

**Step 3: Commit**

```bash
git add Talon/Features/Search/
git commit -m "feat: add SearchView and SearchViewModel with debounced search and history"
```

---

## Phase 4: Preview (Multi-format + Asset Detail)

### Task 17: Create AssetPreviewView

**Files:**
- Create: `Talon/Features/Preview/AssetPreviewView.swift`
- Create: `Talon/Features/Preview/AssetDetailSheet.swift`

**Step 1: Write AssetPreviewView with multi-format support**

```swift
// Talon/Features/Preview/AssetPreviewView.swift
import SwiftUI
import PDFKit
import WebKit

struct AssetPreviewView: View {
    let asset: Asset
    let libraryURL: URL
    @State private var showDetail = false
    @State private var scale: CGFloat = 1.0

    private var fileURL: URL {
        libraryURL
            .appendingPathComponent("images")
            .appendingPathComponent(asset.relativePath)
            .appendingPathComponent("\(asset.name).\(asset.fileExtension)")
    }

    private var thumbnailURL: URL {
        libraryURL
            .appendingPathComponent("images")
            .appendingPathComponent(asset.relativePath)
            .appendingPathComponent("_thumbnail.png")
    }

    var body: some View {
        NavigationStack {
            previewContent
                .navigationTitle(asset.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Info") { showDetail = true }
                    }
                }
                .sheet(isPresented: $showDetail) {
                    AssetDetailSheet(asset: asset)
                }
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch asset.fileExtension.lowercased() {
        case "jpg", "jpeg", "png", "webp", "heic", "bmp", "tiff":
            imagePreview
        case "gif":
            gifPreview
        case "svg":
            svgPreview
        case "pdf":
            pdfPreview
        default:
            // Fallback: show thumbnail with format badge
            fallbackPreview
        }
    }

    private var imagePreview: some View {
        ZoomableImageView(url: fileURL, fallbackURL: thumbnailURL)
    }

    private var gifPreview: some View {
        // Use thumbnail as static preview for now
        ZoomableImageView(url: fileURL, fallbackURL: thumbnailURL)
    }

    private var svgPreview: some View {
        SVGWebView(url: fileURL)
    }

    private var pdfPreview: some View {
        PDFPreviewView(url: fileURL)
    }

    private var fallbackPreview: some View {
        VStack(spacing: BrandSpacing.cardContent) {
            ZoomableImageView(url: thumbnailURL, fallbackURL: thumbnailURL)
            Text(asset.fileExtension.uppercased())
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.Background.card)
                .clipShape(Capsule())
                .foregroundStyle(Color.Text.secondary)
        }
    }
}

// Zoomable image
struct ZoomableImageView: View {
    let url: URL
    let fallbackURL: URL

    var body: some View {
        if let image = UIImage(contentsOfFile: url.path) ?? UIImage(contentsOfFile: fallbackURL.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            ContentUnavailableView("Cannot load image", systemImage: "photo")
        }
    }
}

// SVG via WKWebView
struct SVGWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

// PDF preview
struct PDFPreviewView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {}
}
```

**Step 2: Write AssetDetailSheet**

```swift
// Talon/Features/Preview/AssetDetailSheet.swift
import SwiftUI

struct AssetDetailSheet: View {
    let asset: Asset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("File Info") {
                    row("Name", asset.name)
                    row("Format", asset.fileExtension.uppercased())
                    row("Size", ByteCountFormatter.string(
                        fromByteCount: asset.fileSize, countStyle: .file))
                    row("Dimensions", "\(asset.width) x \(asset.height)")
                }

                if asset.rating > 0 {
                    Section("Rating") {
                        HStack {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= asset.rating ? "star.fill" : "star")
                                    .foregroundStyle(star <= asset.rating ? Color.brandYellow : Color.Text.quaternary)
                            }
                        }
                    }
                }

                if let annotation = asset.annotation, !annotation.isEmpty {
                    Section("Notes") {
                        Text(annotation)
                            .foregroundStyle(Color.Text.primary)
                    }
                }

                if let url = asset.sourceURL, !url.isEmpty {
                    Section("Source") {
                        Text(url)
                            .foregroundStyle(Color.brandBlue)
                            .lineLimit(2)
                    }
                }

                Section("Dates") {
                    row("Created", asset.createdAt.formatted())
                    row("Modified", asset.modifiedAt.formatted())
                    row("Imported", asset.importedAt.formatted())
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.Text.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(Color.Text.primary)
        }
    }
}
```

**Step 3: Commit**

```bash
git add Talon/Features/Preview/
git commit -m "feat: add AssetPreviewView with multi-format support and detail sheet"
```

---

## Phase 5: Polish (Offline Cache + SMB + Settings)

### Task 18: Create DiskCacheManager

**Files:**
- Create: `Talon/Services/DiskCacheManager.swift`

**Step 1: Write disk cache manager for thumbnails and originals**

```swift
// Talon/Services/DiskCacheManager.swift
import Foundation

actor DiskCacheManager {
    private let thumbnailDir: URL
    private let originalDir: URL
    private let maxCacheSize: Int64 // bytes

    init(maxCacheSizeMB: Int = 2048) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        thumbnailDir = appSupport.appendingPathComponent("Talon/Thumbnails")
        originalDir = appSupport.appendingPathComponent("Talon/Originals")
        maxCacheSize = Int64(maxCacheSizeMB) * 1024 * 1024

        try? FileManager.default.createDirectory(at: thumbnailDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: originalDir, withIntermediateDirectories: true)

        // Exclude from iCloud backup
        var thumbURL = thumbnailDir
        var origURL = originalDir
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? thumbURL.setResourceValues(resourceValues)
        try? origURL.setResourceValues(resourceValues)
    }

    func cachedThumbnailURL(assetID: String) -> URL {
        thumbnailDir.appendingPathComponent("\(assetID).png")
    }

    func cachedOriginalURL(assetID: String, ext: String) -> URL {
        originalDir.appendingPathComponent("\(assetID).\(ext)")
    }

    func hasCachedThumbnail(assetID: String) -> Bool {
        FileManager.default.fileExists(atPath: cachedThumbnailURL(assetID: assetID).path)
    }

    func cacheThumbnail(assetID: String, from sourceURL: URL) throws {
        let dest = cachedThumbnailURL(assetID: assetID)
        if FileManager.default.fileExists(atPath: dest.path) { return }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
    }

    func cacheOriginal(assetID: String, ext: String, from sourceURL: URL) throws {
        try evictIfNeeded()
        let dest = cachedOriginalURL(assetID: ext, ext: ext)
        if FileManager.default.fileExists(atPath: dest.path) { return }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
    }

    /// LRU eviction: delete oldest accessed files until under size limit
    func evictIfNeeded() throws {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: originalDir,
            includingPropertiesForKeys: [.contentAccessDateKey, .fileSizeKey]
        )

        var totalSize: Int64 = 0
        var files: [(url: URL, accessDate: Date, size: Int64)] = []

        for url in contents {
            let values = try url.resourceValues(forKeys: [.contentAccessDateKey, .fileSizeKey])
            let size = Int64(values.fileSize ?? 0)
            let date = values.contentAccessDate ?? .distantPast
            totalSize += size
            files.append((url, date, size))
        }

        guard totalSize > maxCacheSize else { return }

        // Sort by access date, oldest first
        files.sort { $0.accessDate < $1.accessDate }

        for file in files {
            guard totalSize > maxCacheSize else { break }
            try fm.removeItem(at: file.url)
            totalSize -= file.size
        }
    }

    func clearAllCache() throws {
        let fm = FileManager.default
        try? fm.removeItem(at: thumbnailDir)
        try? fm.removeItem(at: originalDir)
        try fm.createDirectory(at: thumbnailDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: originalDir, withIntermediateDirectories: true)
    }

    func cacheSize() throws -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        for dir in [thumbnailDir, originalDir] {
            let contents = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])
            for url in contents {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }
}
```

**Step 2: Commit**

```bash
git add Talon/Services/DiskCacheManager.swift
git commit -m "feat: add DiskCacheManager with LRU eviction and iCloud backup exclusion"
```

---

### Task 19: Create Settings View

**Files:**
- Create: `Talon/Features/Settings/SettingsView.swift`

**Step 1: Write settings view**

```swift
// Talon/Features/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("maxCacheSizeMB") private var maxCacheSizeMB = 2048
    @State private var currentCacheSize: String = "Calculating..."
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Cache") {
                    HStack {
                        Text("Used")
                            .foregroundStyle(Color.Text.secondary)
                        Spacer()
                        Text(currentCacheSize)
                            .foregroundStyle(Color.Text.primary)
                    }

                    Picker("Max Cache", selection: $maxCacheSizeMB) {
                        Text("500 MB").tag(500)
                        Text("1 GB").tag(1024)
                        Text("2 GB").tag(2048)
                        Text("5 GB").tag(5120)
                        Text("10 GB").tag(10240)
                    }

                    Button("Clear Cache", role: .destructive) {
                        showClearConfirmation = true
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                            .foregroundStyle(Color.Text.secondary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(Color.Text.primary)
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Clear all cached files?", isPresented: $showClearConfirmation) {
                Button("Clear Cache", role: .destructive) {
                    Task {
                        let cache = DiskCacheManager(maxCacheSizeMB: maxCacheSizeMB)
                        try? await cache.clearAllCache()
                        await updateCacheSize()
                    }
                }
            }
            .task { await updateCacheSize() }
        }
    }

    private func updateCacheSize() async {
        let cache = DiskCacheManager(maxCacheSizeMB: maxCacheSizeMB)
        if let size = try? await cache.cacheSize() {
            currentCacheSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }
}
```

**Step 2: Commit**

```bash
git add Talon/Features/Settings/SettingsView.swift
git commit -m "feat: add SettingsView with cache management"
```

---

### Task 20: Create Main TabView and Wire Everything Together

**Files:**
- Modify: `Talon/TalonApp.swift`
- Modify: `Talon/ContentView.swift`

**Step 1: Update ContentView to main tab structure**

```swift
// Talon/ContentView.swift
import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var database: AppDatabase?
    @State private var libraryURL: URL?
    @State private var showLibraryPicker = false
    @State private var accessManager = ScopedAccessManager()

    var body: some View {
        Group {
            if let database, let libraryURL {
                TabView(selection: $selectedTab) {
                    Tab("Browse", systemImage: "photo.on.rectangle", value: 0) {
                        LibraryBrowserView(database: database, libraryURL: libraryURL)
                    }
                    Tab("Search", systemImage: "magnifyingglass", value: 1) {
                        SearchView(database: database, libraryURL: libraryURL)
                    }
                    Tab("Settings", systemImage: "gearshape", value: 2) {
                        SettingsView()
                    }
                }
                .tint(Color.brand)
            } else {
                welcomeView
            }
        }
        .task {
            // Try to restore last opened library
            let paths = await accessManager.savedLibraryPaths()
            if let lastPath = paths.first,
               let url = try? await accessManager.resolveBookmark(for: lastPath) {
                await openLibrary(at: url)
            }
        }
    }

    private var welcomeView: some View {
        VStack(spacing: BrandSpacing.cardContent) {
            Image(systemName: "eagle")
                .font(.system(size: 80))
                .foregroundStyle(Color.brand)

            Text("Talon")
                .font(.zhdh(size: 36))
                .foregroundStyle(Color.Text.primary)

            Text("Open your Eagle library to get started")
                .foregroundStyle(Color.Text.secondary)

            Button {
                showLibraryPicker = true
            } label: {
                Label("Open Library", systemImage: "folder")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.brand)
                    .foregroundStyle(Color.Text.inverse)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .fileImporter(
            isPresented: $showLibraryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await openLibrary(at: url) }
            }
        }
    }

    private func openLibrary(at url: URL) async {
        do {
            try await accessManager.saveBookmark(for: url)
            let dbPath = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Talon/Databases")
            try FileManager.default.createDirectory(at: dbPath, withIntermediateDirectories: true)

            let libraryName = url.deletingPathExtension().lastPathComponent
            let dbFile = dbPath.appendingPathComponent("\(libraryName).sqlite").path
            let db = try AppDatabase.openLibrary(at: dbFile)

            self.database = db
            self.libraryURL = url

            // Index if empty
            let count = try await db.dbWriter.read { db in
                try Asset.fetchCount(db)
            }
            if count == 0 {
                let indexer = LibraryIndexer(database: db)
                try await indexer.indexLibrary(libraryURL: url) { _, _ in }
            }
        } catch {
            // Handle error
        }
    }
}
```

**Step 2: Commit**

```bash
git add Talon/ContentView.swift
git commit -m "feat: wire up main TabView with Browse, Search, Settings tabs"
```

---

## Phase 6: App Store Readiness

### Task 21: Add App Icon and Launch Screen

**Files:**
- Modify: `Talon/Assets.xcassets`

**Step 1:** Design and add app icon to the asset catalog. Use a stylized eagle talon/claw icon with the brand primary color (#6C6FFA).

**Step 2: Commit**

```bash
git add Talon/Assets.xcassets
git commit -m "feat: add app icon and launch screen"
```

---

### Task 22: Configure App Store Metadata

**Files:**
- Create: `docs/appstore-metadata.md`

**Step 1:** Prepare App Store listing content:

- App name: Talon - Eagle Library Viewer
- Subtitle: Browse your design assets on the go
- Category: Productivity
- Keywords: eagle, design, assets, library, browse, search, tags
- Description: (bilingual CN/EN)
- Screenshots: iPhone (6.7", 6.1"), iPad (12.9")
- Privacy policy URL
- Support URL

**Step 2: Commit**

```bash
git add docs/appstore-metadata.md
git commit -m "docs: add App Store metadata and listing content"
```

---

### Task 23: Performance Testing and Optimization

**Step 1:** Create a test Eagle library with 1,000+ assets for performance validation

**Step 2:** Run performance benchmarks against targets:
- First index 1,000 assets: < 10s
- FTS5 search: < 50ms
- Scroll performance: >= 55fps
- Memory usage: < 150MB

**Step 3:** Profile with Instruments (Time Profiler, Allocations, Core Animation)

**Step 4:** Fix any performance issues found

**Step 5: Commit optimizations**

```bash
git add -A && git commit -m "perf: optimize for App Store readiness benchmarks"
```

---

### Task 24: TestFlight and App Store Submission

**Step 1:** Archive the app: `xcodebuild archive -scheme Talon -archivePath Talon.xcarchive`

**Step 2:** Upload to App Store Connect via Xcode Organizer or `altool`

**Step 3:** Submit for TestFlight internal testing

**Step 4:** After 1-2 weeks of testing, submit for App Store review

---

## Summary

| Phase | Tasks | Description |
|-------|-------|-------------|
| Phase 1 | 1-9 | Foundation: GRDB models, Eagle parser, file access |
| Phase 2 | 10-14 | Browse: thumbnails, layouts, folder navigation |
| Phase 3 | 15-16 | Search: FTS5, multi-filter, search UI |
| Phase 4 | 17 | Preview: multi-format viewer, asset details |
| Phase 5 | 18-20 | Polish: disk cache, settings, main tab wiring |
| Phase 6 | 21-24 | Ship: icon, metadata, perf testing, submission |

Total: 24 tasks across 6 phases
