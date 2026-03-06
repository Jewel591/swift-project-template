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
