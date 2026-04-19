import Foundation

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
}
