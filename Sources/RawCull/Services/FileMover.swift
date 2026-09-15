import Foundation

/// Counts across every folder under a root that has a session file.
struct SessionTotals: Equatable {
    let folders: Int
    let picks: Int
    let rejects: Int
    let undecided: Int
}

/// Outcome of moving every folder under a root.
struct TreeMoveResult: Equatable {
    let folders: Int
    let picks: Int
    let rejects: Int
}

struct FileMover {
    enum MoveError: LocalizedError {
        case noFolder
        case createDirectoryFailed(String)
        case moveFailed(String, String)

        var errorDescription: String? {
            switch self {
            case .noFolder:
                return "No source folder set"
            case .createDirectoryFailed(let path):
                return "Failed to create directory: \(path)"
            case .moveFailed(let file, let reason):
                return "Failed to move \(file): \(reason)"
            }
        }
    }

    /// Moves picked and rejected files into subfolders. Returns (picksMoved, rejectsMoved).
    static func moveFiles(
        items: [PhotoItem],
        folderURL: URL,
        progress: @escaping (Int, Int) -> Void
    ) throws -> (picks: Int, rejects: Int) {
        let fm = FileManager.default
        let picksDir = folderURL.appendingPathComponent("Picks")
        let rejectsDir = folderURL.appendingPathComponent("Rejects")

        // Create directories
        for dir in [picksDir, rejectsDir] {
            if !fm.fileExists(atPath: dir.path) {
                do {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                } catch {
                    throw MoveError.createDirectoryFailed(dir.path)
                }
            }
        }

        let decidedItems = items.filter { $0.decision != .undecided }
        var picksMoved = 0
        var rejectsMoved = 0

        for (index, item) in decidedItems.enumerated() {
            let targetDir = item.decision == .pick ? picksDir : rejectsDir
            let destination = targetDir.appendingPathComponent(item.url.lastPathComponent)

            do {
                try fm.moveItem(at: item.url, to: destination)
                if item.decision == .pick { picksMoved += 1 }
                else { rejectsMoved += 1 }
            } catch {
                throw MoveError.moveFailed(item.filename, error.localizedDescription)
            }

            progress(index + 1, decidedItems.count)
        }

        return (picks: picksMoved, rejects: rejectsMoved)
    }

    // MARK: - Whole tree

    /// Totals over every folder under `rootURL` (root included) that has a
    /// session file. Decisions for files that no longer exist are ignored.
    static func sessionTotals(rootURL: URL) -> SessionTotals {
        var folders = 0
        var picks = 0
        var rejects = 0
        var undecided = 0

        for folderURL in allFolders(under: rootURL) {
            guard let items = sessionItems(in: folderURL) else { continue }
            folders += 1
            for item in items {
                switch item.decision {
                case .pick: picks += 1
                case .reject: rejects += 1
                case .undecided: undecided += 1
                }
            }
        }

        return SessionTotals(folders: folders, picks: picks, rejects: rejects, undecided: undecided)
    }

    /// Moves picks and rejects in every folder under `rootURL` into that
    /// folder's own `Picks/` and `Rejects/`, then deletes that folder's session
    /// file. Folders without a session, or with no decided photos, are left
    /// untouched. `progress` receives (moved so far, total to move) across all
    /// folders. Stops at the first failing move; folders already processed stay
    /// moved.
    static func moveAllSessions(
        rootURL: URL,
        progress: @escaping (Int, Int) -> Void
    ) throws -> TreeMoveResult {
        var pending: [(folderURL: URL, items: [PhotoItem])] = []
        for folderURL in allFolders(under: rootURL) {
            guard let items = sessionItems(in: folderURL),
                  items.contains(where: { $0.decision != .undecided }) else { continue }
            pending.append((folderURL, items))
        }

        let total = pending.reduce(0) { sum, entry in
            sum + entry.items.filter { $0.decision != .undecided }.count
        }

        var movedSoFar = 0
        var folders = 0
        var picks = 0
        var rejects = 0

        for entry in pending {
            let base = movedSoFar
            let result = try moveFiles(items: entry.items, folderURL: entry.folderURL) { completed, _ in
                progress(base + completed, total)
            }
            movedSoFar += result.picks + result.rejects
            folders += 1
            picks += result.picks
            rejects += result.rejects
            try? FileManager.default.removeItem(at: SavedSession.url(in: entry.folderURL))
        }

        return TreeMoveResult(folders: folders, picks: picks, rejects: rejects)
    }

    /// Root first, then descendants depth-first, in tree order.
    private static func allFolders(under rootURL: URL) -> [URL] {
        var urls: [URL] = []
        func walk(_ node: FolderNode) {
            urls.append(node.url)
            for child in node.children {
                walk(child)
            }
        }
        walk(FolderScanner.folderTree(rootURL: rootURL))
        return urls
    }

    /// The folder's current photos with the session's decision applied, or nil
    /// when the folder has no session file.
    private static func sessionItems(in folderURL: URL) -> [PhotoItem]? {
        guard let saved = SavedSession.load(from: folderURL) else { return nil }
        return FolderScanner.scan(folderURL: folderURL).map { url in
            PhotoItem(url: url, decision: saved.decisions[url.lastPathComponent] ?? .undecided)
        }
    }
}
