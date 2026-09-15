import SwiftUI

/// Sidebar tree of the root folder and its subfolders. Selecting a row asks
/// the owner to switch the culling session to that folder.
struct FolderTreePanel: View {
    let root: FolderNode
    let selectedURL: URL?
    @Binding var expandedURLs: Set<URL>
    let onSelect: (URL) -> Void

    var body: some View {
        List(selection: selectionBinding) {
            FolderTreeRow(node: root, expandedURLs: $expandedURLs)
        }
        .listStyle(.sidebar)
        .onAppear {
            expandedURLs.insert(root.url)
        }
        .onChange(of: root) { _, newRoot in
            expandedURLs.insert(newRoot.url)
        }
    }

    /// Maps the session's folder URL onto the matching tree node by path, and
    /// forwards row clicks to `onSelect`.
    private var selectionBinding: Binding<URL?> {
        Binding(
            get: {
                guard let selectedPath = selectedURL?.path else { return nil }
                return root.first(where: { $0.url.path == selectedPath })?.url
            },
            set: { newValue in
                if let newValue {
                    onSelect(newValue)
                }
            }
        )
    }
}

private struct FolderTreeRow: View {
    let node: FolderNode
    @Binding var expandedURLs: Set<URL>

    var body: some View {
        if node.children.isEmpty {
            label
        } else {
            DisclosureGroup(isExpanded: expansionBinding) {
                ForEach(node.children) { child in
                    FolderTreeRow(node: child, expandedURLs: $expandedURLs)
                }
            } label: {
                label
            }
        }
    }

    private var label: some View {
        Label(node.name, systemImage: "folder")
            .lineLimit(1)
            .truncationMode(.middle)
            .tag(node.url)
    }

    private var expansionBinding: Binding<Bool> {
        Binding(
            get: { expandedURLs.contains(node.url) },
            set: { isExpanded in
                if isExpanded {
                    expandedURLs.insert(node.url)
                } else {
                    expandedURLs.remove(node.url)
                }
            }
        )
    }
}
