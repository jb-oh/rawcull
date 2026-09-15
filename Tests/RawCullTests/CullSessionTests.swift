import Foundation
import Testing
@testable import RawCull

@MainActor
struct CullSessionTests {

    private func makeFolder(files: [String]) throws -> URL {
        let fileManager = FileManager.default
        let dir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in files {
            fileManager.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
        }
        return dir
    }

    private func savedDecisions(in folder: URL) throws -> [String: String]? {
        let sessionURL = folder.appendingPathComponent(".rawcull-session.json")
        guard FileManager.default.fileExists(atPath: sessionURL.path) else { return nil }
        let data = try Data(contentsOf: sessionURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["decisions"] as? [String: String]
    }

    @Test func flushSaveWritesPendingDecisionImmediately() throws {
        let folder = try makeFolder(files: ["a.png", "b.png"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let session = CullSession()
        session.load(folderURL: folder, fileURLs: FolderScanner.scan(folderURL: folder))
        session.markPick()

        // Debounced save has not fired yet.
        #expect(try savedDecisions(in: folder) == nil)

        session.flushSave()

        #expect(try savedDecisions(in: folder)?["a.png"] == "pick")
    }

    @Test func flushSaveWithoutPendingChangesWritesNothing() throws {
        let folder = try makeFolder(files: ["a.png"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let session = CullSession()
        session.load(folderURL: folder, fileURLs: FolderScanner.scan(folderURL: folder))
        session.flushSave()

        #expect(try savedDecisions(in: folder) == nil)
    }

    @Test func loadingAnotherFolderFlushesPreviousFolderAndResumesItLater() throws {
        let folderA = try makeFolder(files: ["a.png"])
        let folderB = try makeFolder(files: ["b.png"])
        defer {
            try? FileManager.default.removeItem(at: folderA)
            try? FileManager.default.removeItem(at: folderB)
        }

        let session = CullSession()
        session.load(folderURL: folderA, fileURLs: FolderScanner.scan(folderURL: folderA))
        session.markReject()

        session.load(folderURL: folderB, fileURLs: FolderScanner.scan(folderURL: folderB))

        #expect(try savedDecisions(in: folderA)?["a.png"] == "reject")
        #expect(try savedDecisions(in: folderB) == nil)
        #expect(session.items.map(\.filename) == ["b.png"])
        #expect(session.rejectCount == 0)

        session.load(folderURL: folderA, fileURLs: FolderScanner.scan(folderURL: folderA))
        #expect(session.items.first?.decision == .reject)
        #expect(session.rejectCount == 1)
    }

    @Test func deleteSessionFileCancelsPendingSave() async throws {
        let folder = try makeFolder(files: ["a.png"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let session = CullSession()
        session.load(folderURL: folder, fileURLs: FolderScanner.scan(folderURL: folder))
        session.markPick()
        session.deleteSessionFile()

        // Wait past the one second debounce; the cancelled save must not recreate the file.
        try await Task.sleep(for: .seconds(1.5))
        #expect(try savedDecisions(in: folder) == nil)
    }

    @Test func pendingFlagSurvivesFailedWrite() throws {
        let folder = try makeFolder(files: ["a.png"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let session = CullSession()
        session.load(folderURL: folder, fileURLs: FolderScanner.scan(folderURL: folder))
        session.markPick()

        // Delete the folder to cause the write to fail.
        try FileManager.default.removeItem(at: folder)

        // flushSave() will attempt to write but fail (folder doesn't exist).
        session.flushSave()

        // Recreate the folder so we can write to it again.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // flushSave() again; the flag should still be set, so it writes now.
        session.flushSave()

        #expect(try savedDecisions(in: folder)?["a.png"] == "pick")
    }
}
