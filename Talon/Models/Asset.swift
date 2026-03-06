import Foundation
import GRDB

struct Asset: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: String              // Eagle 13-digit random ID
    var name: String
    var fileExtension: String
    var fileSize: Int64
    var width: Int
    var height: Int
    var rating: Int
    var sourceURL: String?
    var annotation: String?
    var createdAt: Date
    var modifiedAt: Date
    var importedAt: Date
    var relativePath: String
    var thumbnailPath: String
    var primaryColorHex: String?
    var palettesJSON: String?
    var thumbnailCached: Bool
    var originalCached: Bool
    var lastAccessedAt: Date?

    static let assetTags = hasMany(AssetTag.self)
    static let assetFolders = hasMany(AssetFolder.self)
}
