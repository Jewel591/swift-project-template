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
