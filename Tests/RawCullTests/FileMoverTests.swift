import Foundation
import Testing
@testable import RawCull

struct FileMoverTests {

    /// Builds:
    ///   root/A/            session: a1 pick, a2 reject, a3 undecided
    ///   root/A/Sub/        session: s1 pick
    ///   root/B/            no session, b1
    ///   root/C/            session with c1 undecided only
    private func makeFixture() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for path in ["A/Sub", "B", "C"] {
            try fm.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        for path in ["A/a1.png", "A/a2.png", "A/a3.png", "A/Sub/s1.png", "B/b1.png", "C/c1.png"] {
            fm.createFile(atPath: root.appendingPathComponent(path).path, contents: Data())
        }
        try writeSession(in: root.appendingPathComponent("A"), decisions: ["a1.png": .pick, "a2.png": .reject])
        try writeSession(in: root.appendingPathComponent("A/Sub"), decisions: ["s1.png": .pick])
        try writeSession(in: root.appendingPathComponent("C"), decisions: ["c1.png": .undecided])
        return root
    }

    private func writeSession(in folder: URL, decisions: [String: Decision]) throws {
        let saved = SavedSession(version: 1, currentIndex: 0, decisions: decisions)
        let data = try JSONEncoder().encode(saved)
        try data.write(to: SavedSession.url(in: folder))
    }

    private func exists(_ root: URL, _ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    @Test func sessionTotalsCountsEveryFolderWithASession() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let totals = FileMover.sessionTotals(rootURL: root)

        #expect(totals == SessionTotals(folders: 3, picks: 2, rejects: 1, undecided: 2))
    }

    @Test func moveAllSessionsMovesEachFolderIntoItsOwnSubfolders() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        var lastProgress: (Int, Int) = (0, 0)
        let result = try FileMover.moveAllSessions(rootURL: root) { completed, total in
            lastProgress = (completed, total)
        }

        #expect(result == TreeMoveResult(folders: 2, picks: 2, rejects: 1))
        #expect(lastProgress == (3, 3))

        #expect(exists(root, "A/Picks/a1.png"))
        #expect(exists(root, "A/Rejects/a2.png"))
        #expect(exists(root, "A/a3.png"))
        #expect(exists(root, "A/Sub/Picks/s1.png"))
        #expect(exists(root, "B/b1.png"))
        #expect(exists(root, "C/c1.png"))

        #expect(!exists(root, "Picks"))
        #expect(!exists(root, "C/Picks"))
        #expect(!exists(root, "A/.rawcull-session.json"))
        #expect(!exists(root, "A/Sub/.rawcull-session.json"))
        #expect(exists(root, "C/.rawcull-session.json"))
    }

    @Test func moveAllSessionsIgnoresDecisionsForMissingFiles() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("A/a1.png"))

        let result = try FileMover.moveAllSessions(rootURL: root) { _, _ in }

        #expect(result == TreeMoveResult(folders: 2, picks: 1, rejects: 1))
        #expect(!exists(root, "A/Picks/a1.png"))
        #expect(exists(root, "A/Rejects/a2.png"))
    }

    @Test func moveAllSessionsIncludesTheRootFolderItself() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        FileManager.default.createFile(atPath: root.appendingPathComponent("r1.png").path, contents: Data())
        try writeSession(in: root, decisions: ["r1.png": .pick])

        #expect(FileMover.sessionTotals(rootURL: root) == SessionTotals(folders: 4, picks: 3, rejects: 1, undecided: 2))

        let result = try FileMover.moveAllSessions(rootURL: root) { _, _ in }

        #expect(result == TreeMoveResult(folders: 3, picks: 3, rejects: 1))
        #expect(exists(root, "Picks/r1.png"))
        #expect(!exists(root, ".rawcull-session.json"))
    }

    @Test func moveAllSessionsStopsAtTheFirstFailureAndNamesTheFolder() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        // Make A/Sub/Picks/s1.png already exist so its move collides.
        let subPicks = root.appendingPathComponent("A/Sub/Picks")
        try FileManager.default.createDirectory(at: subPicks, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: subPicks.appendingPathComponent("s1.png").path, contents: Data())

        do {
            _ = try FileMover.moveAllSessions(rootURL: root) { _, _ in }
            Issue.record("expected throw")
        } catch let error as FileMover.MoveError {
            #expect(error.errorDescription?.contains("Sub/s1.png") == true)
        }

        // A was walked first and stays moved, with its session gone.
        #expect(exists(root, "A/Picks/a1.png"))
        #expect(!exists(root, "A/.rawcull-session.json"))
        // A/Sub failed, so its session file must survive.
        #expect(exists(root, "A/Sub/.rawcull-session.json"))
    }
}
