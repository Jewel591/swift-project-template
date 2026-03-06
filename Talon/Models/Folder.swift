import Foundation
import GRDB

struct Folder: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: String
    var name: String
    var parentID: String?

    static let parent = belongsTo(Folder.self, key: "parent", using: ForeignKey(["parentID"]))
    static let children = hasMany(Folder.self, key: "children", using: ForeignKey(["parentID"]))
    static let assetFolders = hasMany(AssetFolder.self)
}
