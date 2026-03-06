import Foundation

/// Maps to Eagle's tags.json entries
struct TagDTO: Codable {
    let id: String
    let name: String
    let color: String?
}

extension TagDTO {
    func toTag() -> Tag {
        Tag(name: name, color: color)
    }
}
