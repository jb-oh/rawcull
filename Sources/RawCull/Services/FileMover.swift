import Foundation

/// Folders created by Move Files carry their decision when no saved override exists.
struct SortedFolder {
    let decision: Decision
    let parentURL: URL
    let siblingURL: URL

    init?(folderURL: URL) {
        let folderURL = folderURL.standardizedFileURL
        let parentURL = folderURL.deletingLastPathComponent()
        guard folderURL.isFileURL, parentURL.path != folderURL.path else { return nil }
        switch folderURL.lastPathComponent {
        case "Picks":
            decision = .pick
            siblingURL = parentURL.appendingPathComponent("Rejects")
        case "Rejects":
            decision = .reject
            siblingURL = parentURL.appendingPathComponent("Picks")
        default:
            return nil
        }
        self.parentURL = parentURL
    }

    func destination(for decision: Decision) -> URL? {
        guard decision != self.decision else { return nil }
        return decision == .undecided ? parentURL : siblingURL
    }
}

/// Counts across every folder under a root that has a session file.
struct SessionTotals: Equatable {
    let folders: Int
    let picks: Int
    let rejects: Int
    let undecided: Int
    let filesToMove: Int
}

/// Counts by destination, excluding photos that stayed in place.
struct MoveResult: Equatable {
    let picks: Int
    let rejects: Int
    let returnedToParent: Int

    var totalMoved: Int { picks + rejects + returnedToParent }
}

/// Outcome of moving every folder under a root.
struct TreeMoveResult: Equatable {
    let folders: Int
    let picks: Int
    let rejects: Int
    let returnedToParent: Int
}

struct FileMover {
    enum MoveError: LocalizedError {
        case noFolder
        case createDirectoryFailed(String)
        case moveFailed(String, String)

        var errorDescription: String? {
            switch self {
            case .noFolder:
                return String(localized: "No source folder set", bundle: Localization.bundle)
            case .createDirectoryFailed(let path):
                return String(localized: "Failed to create directory: \(path)", bundle: Localization.bundle)
            case .moveFailed(let file, let reason):
                return String(localized: "Failed to move \(file): \(reason)", bundle: Localization.bundle)
            }
        }
    }

    /// Moves decisions into subfolders, or re-sorts photos already in a sorted folder.
    static func moveFiles(
        items: [PhotoItem],
        folderURL: URL,
        progress: @escaping (Int, Int) -> Void
    ) throws -> MoveResult {
        let fm = FileManager.default
        let moves = items.compactMap { item -> (item: PhotoItem, directory: URL)? in
            guard let directory = destination(for: item.decision, in: folderURL) else { return nil }
            return (item, directory)
        }

        let directories: [URL]
        if SortedFolder(folderURL: folderURL) != nil {
            directories = Set(moves.map(\.directory)).sorted { $0.path < $1.path }
        } else {
            // Preserve ordinary folders' directory creation even when no photos move.
            directories = [folderURL.appendingPathComponent("Picks"), folderURL.appendingPathComponent("Rejects")]
        }

        // Create directories
        for dir in directories {
            if !fm.fileExists(atPath: dir.path) {
                do {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                } catch {
                    throw MoveError.createDirectoryFailed(dir.path)
                }
            }
        }

        var picksMoved = 0
        var rejectsMoved = 0
        var returnedToParent = 0

        for (index, move) in moves.enumerated() {
            let (item, targetDir) = move
            let destination = targetDir.appendingPathComponent(item.url.lastPathComponent)

            do {
                try fm.moveItem(at: item.url, to: destination)
                switch item.decision {
                case .pick: picksMoved += 1
                case .reject: rejectsMoved += 1
                case .undecided: returnedToParent += 1
                }
            } catch {
                throw MoveError.moveFailed(item.filename, error.localizedDescription)
            }

            if RotationWriter.isRAW(item.url) {
                let sidecar = RotationWriter.sidecarURL(for: item.url)
                if fm.fileExists(atPath: sidecar.path) {
                    do {
                        try fm.moveItem(at: sidecar, to: targetDir.appendingPathComponent(sidecar.lastPathComponent))
                    } catch {
                        // Like a photo failure, stop and report without rolling back completed moves.
                        throw MoveError.moveFailed(sidecar.lastPathComponent, error.localizedDescription)
                    }
                }
            }

            progress(index + 1, moves.count)
        }

        return MoveResult(picks: picksMoved, rejects: rejectsMoved, returnedToParent: returnedToParent)
    }

    static func moveCount(items: [PhotoItem], folderURL: URL) -> Int {
        items.filter { destination(for: $0.decision, in: folderURL) != nil }.count
    }

    private static func destination(for decision: Decision, in folderURL: URL) -> URL? {
        if let sortedFolder = SortedFolder(folderURL: folderURL) {
            return sortedFolder.destination(for: decision)
        }
        switch decision {
        case .pick: return folderURL.appendingPathComponent("Picks")
        case .reject: return folderURL.appendingPathComponent("Rejects")
        case .undecided: return nil
        }
    }

    // MARK: - Whole tree

    /// Totals over every folder under `rootURL` (root included) that has a
    /// session file. Decisions for files that no longer exist are ignored.
    static func sessionTotals(rootURL: URL) -> SessionTotals {
        var folders = 0
        var picks = 0
        var rejects = 0
        var undecided = 0
        var filesToMove = 0

        for folderURL in allFolders(under: rootURL) {
            guard let items = sessionItems(in: folderURL) else { continue }
            folders += 1
            filesToMove += moveCount(items: items, folderURL: folderURL)
            for item in items {
                switch item.decision {
                case .pick: picks += 1
                case .reject: rejects += 1
                case .undecided: undecided += 1
                }
            }
        }

        return SessionTotals(folders: folders, picks: picks, rejects: rejects, undecided: undecided, filesToMove: filesToMove)
    }

    /// Sorts every folder under `rootURL` according to its decisions, then deletes
    /// that folder's session file. Folders without a session, or with no photos
    /// to move, are left untouched. `progress` receives (moved so far, total to move) across all
    /// folders. Stops at the first failing move; folders already processed stay
    /// moved.
    static func moveAllSessions(
        rootURL: URL,
        progress: @escaping (Int, Int) -> Void
    ) throws -> TreeMoveResult {
        var pending: [(folderURL: URL, items: [PhotoItem])] = []
        for folderURL in allFolders(under: rootURL) {
            guard let items = sessionItems(in: folderURL),
                  moveCount(items: items, folderURL: folderURL) > 0 else { continue }
            pending.append((folderURL, items))
        }

        let total = pending.reduce(0) { sum, entry in
            sum + moveCount(items: entry.items, folderURL: entry.folderURL)
        }

        var movedSoFar = 0
        var folders = 0
        var picks = 0
        var rejects = 0
        var returnedToParent = 0

        for entry in pending {
            let base = movedSoFar
            let result: MoveResult
            do {
                result = try moveFiles(items: entry.items, folderURL: entry.folderURL) { completed, _ in
                    progress(base + completed, total)
                }
            } catch MoveError.moveFailed(let file, let reason) {
                throw MoveError.moveFailed("\(entry.folderURL.lastPathComponent)/\(file)", reason)
            }
            movedSoFar += result.totalMoved
            folders += 1
            picks += result.picks
            rejects += result.rejects
            returnedToParent += result.returnedToParent
            try? FileManager.default.removeItem(at: SavedSession.url(in: entry.folderURL))
        }

        return TreeMoveResult(folders: folders, picks: picks, rejects: rejects, returnedToParent: returnedToParent)
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
        let defaultDecision = SortedFolder(folderURL: folderURL)?.decision ?? .undecided
        return FolderScanner.scan(folderURL: folderURL).map { url in
            PhotoItem(url: url, decision: saved.decisions[url.lastPathComponent] ?? defaultDecision)
        }
    }
}
