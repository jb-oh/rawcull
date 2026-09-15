import Foundation
import ImageIO
import UniformTypeIdentifiers

struct FolderScanner {
    /// Every type identifier ImageIO can decode, computed once and cached.
    private static let decodableTypeIdentifiers: Set<String> = {
        let identifiers = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        return Set(identifiers)
    }()

    /// True if the file's UTType (from its path extension) conforms to
    /// `UTType.image` and ImageIO can decode it (the type, or a type it
    /// conforms to, is in `CGImageSourceCopyTypeIdentifiers()`).
    static func isSupported(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        guard type.conforms(to: .image) else {
            return false
        }
        return decodableTypeIdentifiers.contains { identifier in
            guard let decodableType = UTType(identifier) else { return false }
            return type.conforms(to: decodableType)
        }
    }

    /// Scans a folder for supported image files, sorted by filename.
    static func scan(folderURL: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            if isSupported(fileURL) {
                urls.append(fileURL)
            }
        }

        // Natural sort by filename (IMG_0001 < IMG_0002 < IMG_0010)
        urls.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return urls
    }

    /// Builds the folder tree rooted at `rootURL`. Hidden folders are skipped
    /// and symbolic links are not followed, so a link back to an ancestor
    /// cannot cause infinite recursion. Children are naturally sorted.
    static func folderTree(rootURL: URL) -> FolderNode {
        FolderNode(
            url: rootURL,
            name: rootURL.lastPathComponent,
            children: subfolderNodes(of: rootURL)
        )
    }

    private static func subfolderNodes(of folderURL: URL) -> [FolderNode] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var nodes: [FolderNode] = []
        for url in contents {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true,
                  values.isDirectory == true else {
                continue
            }
            nodes.append(FolderNode(
                url: url,
                name: url.lastPathComponent,
                children: subfolderNodes(of: url)
            ))
        }

        nodes.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return nodes
    }

    /// Checks if a session file exists in the given folder.
    static func hasExistingSession(in folderURL: URL) -> Bool {
        let sessionURL = folderURL.appendingPathComponent(".rawcull-session.json")
        return FileManager.default.fileExists(atPath: sessionURL.path)
    }
}
