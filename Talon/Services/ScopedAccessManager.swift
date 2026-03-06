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
