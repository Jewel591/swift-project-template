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
