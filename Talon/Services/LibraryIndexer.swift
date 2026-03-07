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

        // Save index timestamp
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "com.talon.lastIndexDate")
        progress(totalCount, totalCount)
    }

    /// Incremental import: only parse assets modified since lastIndexDate
    func incrementalIndex(libraryURL: URL, since lastIndexDate: Date, progress: @escaping (Int, Int) -> Void) async throws {
        let scanner = EagleLibraryScanner()
        let parser = EagleMetadataParser()

        // 1. Re-parse library metadata (folders may have changed)
        let libraryMeta = try scanner.readLibraryMetadata(libraryURL: libraryURL)
        let folders = libraryMeta.folders?.flatMap { $0.toFolders() } ?? []

        // 2. Re-parse tags
        let tagDTOs = try scanner.readTags(libraryURL: libraryURL)
        let tags = tagDTOs.map { $0.toTag() }

        // 3. Scan only modified asset folders
        let modifiedFolders = try scanner.scanModifiedAssetFolders(libraryURL: libraryURL, since: lastIndexDate)
        let totalCount = modifiedFolders.count
        guard totalCount > 0 else {
            progress(0, 0)
            return
        }

        let parsed = try await parser.parseAssets(folders: modifiedFolders)

        // 4. Write changes to database
        try await database.dbWriter.write { db in
            for folder in folders {
                try folder.insert(db, onConflict: .replace)
            }
            for tag in tags {
                try tag.insert(db, onConflict: .replace)
            }

            for (index, (folderURL, dto)) in parsed.enumerated() {
                let relativePath = folderURL.lastPathComponent
                let asset = dto.toAsset(
                    relativePath: relativePath,
                    thumbnailPath: "\(relativePath)/_thumbnail.png"
                )
                try asset.insert(db, onConflict: .replace)

                // Remove old associations then re-insert
                try AssetTag.filter(Column("assetID") == dto.id).deleteAll(db)
                if let tags = dto.tags {
                    for tag in tags {
                        try AssetTag(assetID: dto.id, tag: tag).insert(db, onConflict: .ignore)
                    }
                }

                try AssetFolder.filter(Column("assetID") == dto.id).deleteAll(db)
                if let folderIDs = dto.folders {
                    for folderID in folderIDs {
                        try AssetFolder(assetID: dto.id, folderID: folderID).insert(db, onConflict: .ignore)
                    }
                }

                if (index + 1) % 100 == 0 {
                    progress(index + 1, totalCount)
                }
            }

            // Rebuild FTS5 for updated assets
            for (_, dto) in parsed {
                try db.execute(sql: "DELETE FROM assetFTS WHERE rowid = (SELECT rowid FROM asset WHERE id = ?)", arguments: [dto.id])
                try db.execute(sql: """
                    INSERT INTO assetFTS(rowid, name, tags, annotation)
                    SELECT rowid, name,
                           (SELECT GROUP_CONCAT(tag, ' ') FROM assetTag WHERE assetID = asset.id),
                           annotation
                    FROM asset WHERE id = ?
                """, arguments: [dto.id])
            }
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "com.talon.lastIndexDate")
        progress(totalCount, totalCount)
    }
}
