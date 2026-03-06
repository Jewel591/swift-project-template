import Foundation

/// Maps 1:1 to Eagle's per-asset metadata.json
struct AssetDTO: Codable {
    let id: String
    let name: String
    let size: Int64
    let ext: String
    let width: Int
    let height: Int
    let tags: [String]?
    let folders: [String]?
    let url: String?
    let annotation: String?
    let star: Int?
    let modificationTime: Int64
    let lastModified: Int64
    let palettes: [[PaletteDTO]]?

    struct PaletteDTO: Codable {
        let color: [Int]
        let ratio: Double
    }
}

extension AssetDTO {
    /// Convert Eagle millisecond timestamp to Date
    func toAsset(relativePath: String, thumbnailPath: String) -> Asset {
        Asset(
            id: id,
            name: name,
            fileExtension: ext,
            fileSize: size,
            width: width,
            height: height,
            rating: star ?? 0,
            sourceURL: url,
            annotation: annotation,
            createdAt: Date(timeIntervalSince1970: Double(modificationTime) / 1000.0),
            modifiedAt: Date(timeIntervalSince1970: Double(lastModified) / 1000.0),
            importedAt: Date(timeIntervalSince1970: Double(modificationTime) / 1000.0),
            relativePath: relativePath,
            thumbnailPath: thumbnailPath,
            primaryColorHex: primaryColorHex,
            palettesJSON: palettesJSONString,
            thumbnailCached: false,
            originalCached: false,
            lastAccessedAt: nil
        )
    }

    private var primaryColorHex: String? {
        guard let palettes = palettes, let first = palettes.first?.first else { return nil }
        let rgb = first.color
        guard rgb.count >= 3 else { return nil }
        return String(format: "#%02X%02X%02X", rgb[0], rgb[1], rgb[2])
    }

    private var palettesJSONString: String? {
        guard let palettes = palettes else { return nil }
        guard let data = try? JSONEncoder().encode(palettes) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
