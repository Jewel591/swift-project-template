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
                            return nil
                        }
                    }
                }
            }

            for try await result in group {
                activeCount -= 1
                if let result {
                    results.append(result)
                }
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
