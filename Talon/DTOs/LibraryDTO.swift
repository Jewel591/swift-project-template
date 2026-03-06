import Foundation

/// Maps to Eagle's root metadata.json
struct LibraryDTO: Codable {
    let folders: [FolderDTO]?
    let modificationTime: Int64?
    let applicationVersion: String?
}

struct FolderDTO: Codable {
    let id: String
    let name: String
    let children: [FolderDTO]?
}

extension FolderDTO {
    /// Flatten nested folder tree into Folder records
    func toFolders(parentID: String? = nil) -> [Folder] {
        var result = [Folder(id: id, name: name, parentID: parentID)]
        if let children = children {
            for child in children {
                result.append(contentsOf: child.toFolders(parentID: id))
            }
        }
        return result
    }
}
