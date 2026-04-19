import Foundation
import UniformTypeIdentifiers

struct FolderScanner {
    static let supportedExtensions: Set<String> = [
        "arw", "cr3", "cr2", "nef", "dng", "raf", "orf", "rw2",
        // Also support common image formats for testing
        "jpg", "jpeg", "heic", "tiff", "tif"
    ]

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
            let ext = fileURL.pathExtension.lowercased()
            if supportedExtensions.contains(ext) {
                urls.append(fileURL)
            }
        }

        // Natural sort by filename (IMG_0001 < IMG_0002 < IMG_0010)
        urls.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return urls
    }

    /// Checks if a session file exists in the given folder.
    static func hasExistingSession(in folderURL: URL) -> Bool {
        let sessionURL = folderURL.appendingPathComponent(".rawcull-session.json")
        return FileManager.default.fileExists(atPath: sessionURL.path)
    }
}
