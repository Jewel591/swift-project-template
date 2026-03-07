import SwiftUI
import GRDB
import GRDBQuery

// MARK: - GRDBQuery Integration

/// Makes AppDatabase available to @Query via SwiftUI environment
extension AppDatabase {
    /// Provides a DatabaseContext for GRDBQuery's @Query property wrapper
    var reader: any DatabaseReader {
        dbWriter
    }
}

/// Environment key for injecting AppDatabase into the SwiftUI view hierarchy
private struct AppDatabaseKey: EnvironmentKey {
    static let defaultValue: AppDatabase? = nil
}

extension EnvironmentValues {
    var appDatabase: AppDatabase? {
        get { self[AppDatabaseKey.self] }
        set { self[AppDatabaseKey.self] = newValue }
    }
}

// MARK: - Example @Query Request

/// Reusable request: fetch assets with sorting and optional folder filter
struct AssetListRequest: ValueObservationQueryable {
    static var defaultValue: [Asset] { [] }

    var sortField: SortField
    var sortAscending: Bool
    var folderID: String?
    var limit: Int

    func fetch(_ db: Database) throws -> [Asset] {
        var query = Asset.all()
        if let folderID {
            query = query.joining(required: Asset.assetFolders.filter(Column("folderID") == folderID))
        }
        let ordering: SQLOrderingTerm = sortAscending
            ? Column(sortField.rawValue).asc
            : Column(sortField.rawValue).desc
        return try query
            .order(ordering)
            .limit(limit)
            .fetchAll(db)
    }
}

/// Reusable request: fetch folders by parent ID
struct FolderListRequest: ValueObservationQueryable {
    static var defaultValue: [Folder] { [] }

    var parentID: String?

    func fetch(_ db: Database) throws -> [Folder] {
        if let parentID {
            return try Folder.filter(Column("parentID") == parentID).fetchAll(db)
        } else {
            return try Folder.filter(Column("parentID") == nil).fetchAll(db)
        }
    }
}

/// Reusable request: fetch asset count
struct AssetCountRequest: ValueObservationQueryable {
    static var defaultValue: Int { 0 }

    func fetch(_ db: Database) throws -> Int {
        try Asset.fetchCount(db)
    }
}
