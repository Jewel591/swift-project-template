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

    func navigateToRoot() async {
        breadcrumbs = []
        currentFolder = nil
        childFolders = []
        await loadRootFolders()
    }

    func navigateBack() async {
        breadcrumbs.removeLast()
        currentFolder = breadcrumbs.last
        if let current = currentFolder {
            await navigateToFolder(current)
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
