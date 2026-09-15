import Foundation

/// One folder in the tree shown in the culling screen's folder panel.
struct FolderNode: Identifiable, Hashable {
    let url: URL
    let name: String
    let children: [FolderNode]

    var id: URL { url }

    /// Depth-first search over this node and its descendants.
    func first(where predicate: (FolderNode) -> Bool) -> FolderNode? {
        if predicate(self) { return self }
        for child in children {
            if let found = child.first(where: predicate) {
                return found
            }
        }
        return nil
    }
}
