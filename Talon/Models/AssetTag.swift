import Foundation
import GRDB

struct AssetTag: Codable, FetchableRecord, PersistableRecord {
    var assetID: String
    var tag: String

    static let asset = belongsTo(Asset.self)
}
