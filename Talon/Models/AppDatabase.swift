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

            try db.create(table: "folder") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("parentID", .text).references("folder", onDelete: .cascade)
            }

            try db.create(table: "tag") { t in
                t.primaryKey("name", .text)
                t.column("color", .text)
            }

            try db.create(table: "assetTag") { t in
                t.column("assetID", .text).notNull().references("asset", onDelete: .cascade)
                t.column("tag", .text).notNull()
                t.primaryKey(["assetID", "tag"])
            }

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
    static func empty() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    static func openLibrary(at path: String) throws -> AppDatabase {
        let dbQueue = try DatabaseQueue(path: path)
        return try AppDatabase(dbQueue)
    }
}
