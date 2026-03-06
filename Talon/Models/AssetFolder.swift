import Foundation
import GRDB

struct AssetFolder: Codable, FetchableRecord, PersistableRecord {
    var assetID: String
    var folderID: String

    static let asset = belongsTo(Asset.self)
    static let folder = belongsTo(Folder.self)
}
