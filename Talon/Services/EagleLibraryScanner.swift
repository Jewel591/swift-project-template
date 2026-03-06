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
