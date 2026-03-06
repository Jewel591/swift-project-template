import Foundation
import GRDB

struct Tag: Codable, FetchableRecord, PersistableRecord {
    var name: String
    var color: String?

    static let databaseTableName = "tag"
}

extension Tag {
    enum Columns {
        static let name = Column(CodingKeys.name)
        static let color = Column(CodingKeys.color)
    }
}
