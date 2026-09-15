import Foundation

/// On-disk format of `.rawcull-session.json`. Field names are part of the
/// file format; do not rename them.
struct SavedSession: Codable {
    static let filename = ".rawcull-session.json"

    let version: Int
    let currentIndex: Int
    let decisions: [String: Decision]

    static func url(in folderURL: URL) -> URL {
        folderURL.appendingPathComponent(filename)
    }

    /// Returns nil when the folder has no session file or it cannot be decoded.
    static func load(from folderURL: URL) -> SavedSession? {
        guard let data = try? Data(contentsOf: url(in: folderURL)) else { return nil }
        return try? JSONDecoder().decode(SavedSession.self, from: data)
    }
}
