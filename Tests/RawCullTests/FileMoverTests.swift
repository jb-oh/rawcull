import Foundation
import Testing
@testable import RawCull

struct FileMoverTests {

    @Test(arguments: ["xmp", "XMP"], [Decision.pick, .reject])
    func movingRAWAlsoMovesItsSidecar(ext: String, decision: Decision) throws {
        let root = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let raw = root.appendingPathComponent("x.cr3")
        let sidecar = root.appendingPathComponent("x.\(ext)")
        try Data().write(to: raw)
        try Data("metadata".utf8).write(to: sidecar)

        let result = try FileMover.moveFiles(items: [PhotoItem(url: raw, decision: decision)], folderURL: root) { _, _ in }

        let destination = decision == .pick ? "Picks" : "Rejects"
        #expect(result.picks + result.rejects == 1)
        #expect(exists(root, "\(destination)/x.cr3"))
        #expect(exists(root, "\(destination)/x.\(ext)"))
        #expect(!exists(root, "x.\(ext)"))
    }

    @Test func movingJPEGLeavesThePairedRAWAndItsSidecar() throws {
        let root = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["x.cr3", "x.jpg", "x.xmp"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        _ = try FileMover.moveFiles(
            items: [PhotoItem(url: root.appendingPathComponent("x.jpg"), decision: .pick)], folderURL: root
        ) { _, _ in }

        #expect(exists(root, "Picks/x.jpg"))
        #expect(exists(root, "x.cr3"))
        #expect(exists(root, "x.xmp"))
        #expect(!exists(root, "Picks/x.xmp"))
    }

    @Test func sidecarMoveFailureReportsSidecarAndKeepsCompletedPhotoMove() throws {
        let root = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Picks"), withIntermediateDirectories: true)
        for name in ["x.cr3", "x.xmp", "Picks/x.xmp"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        do {
            _ = try FileMover.moveFiles(
                items: [PhotoItem(url: root.appendingPathComponent("x.cr3"), decision: .pick)], folderURL: root
            ) { _, _ in }
            Issue.record("expected sidecar collision")
        } catch let error as FileMover.MoveError {
            #expect(error.errorDescription?.contains("x.xmp") == true)
        }
        #expect(exists(root, "Picks/x.cr3"))
        #expect(exists(root, "x.xmp"))
    }

    @Test func sortedFolderRecognizesOnlyExactNamesWithAParent() throws {
        let root = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let picks = try #require(SortedFolder(folderURL: root.appendingPathComponent("Picks")))
        #expect(picks.decision == .pick)
        #expect(picks.parentURL.path == root.path)
        #expect(picks.siblingURL.path == root.appendingPathComponent("Rejects").path)
        let rejects = try #require(SortedFolder(folderURL: root.appendingPathComponent("Rejects")))
        #expect(rejects.decision == .reject)
        #expect(rejects.parentURL.path == root.path)
        #expect(rejects.siblingURL.path == root.appendingPathComponent("Picks").path)
        for name in ["picks", "rejects", "PICKS", "Picks backup", "Album"] {
            #expect(SortedFolder(folderURL: root.appendingPathComponent(name)) == nil)
        }
        #expect(SortedFolder(folderURL: URL(fileURLWithPath: "/")) == nil)
    }

    @Test(arguments: ["Picks", "Rejects"], ["xmp", "XMP"])
    func sortedMovesKeepMatchesAndMoveOppositeAndUndecidedWithSidecars(folderName: String, ext: String) throws {
        let root = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let decision: Decision = folderName == "Picks" ? .pick : .reject
        let opposite: Decision = folderName == "Picks" ? .reject : .pick
        let sibling = folderName == "Picks" ? "Rejects" : "Picks"
        for name in ["keep", "opposite", "return"] {
            try Data(name.utf8).write(to: folder.appendingPathComponent("\(name).cr3"))
            try Data("metadata".utf8).write(to: folder.appendingPathComponent("\(name).\(ext)"))
        }
        let items = [
            PhotoItem(url: folder.appendingPathComponent("keep.cr3"), decision: decision),
            PhotoItem(url: folder.appendingPathComponent("opposite.cr3"), decision: opposite),
            PhotoItem(url: folder.appendingPathComponent("return.cr3"), decision: .undecided)
        ]
        var updates: [Int] = []
        let result = try FileMover.moveFiles(items: items, folderURL: folder) { completed, total in
            #expect(total == 2)
            updates.append(completed)
        }

        #expect(result == MoveResult(picks: opposite == .pick ? 1 : 0, rejects: opposite == .reject ? 1 : 0, returnedToParent: 1))
        #expect(FileMover.moveCount(items: items, folderURL: folder) == 2)
        #expect(updates == [1, 2])
        for ext in ["cr3", ext] {
            #expect(exists(root, "\(folderName)/keep.\(ext)"))
            #expect(exists(root, "\(sibling)/opposite.\(ext)"))
            #expect(exists(root, "return.\(ext)"))
            #expect(!exists(folder, "opposite.\(ext)"))
            #expect(!exists(folder, "return.\(ext)"))
        }
        #expect(!exists(folder, "Picks"))
        #expect(!exists(folder, "Rejects"))
    }

    @Test(arguments: ["Picks", "Rejects"], [false, true])
    func sortedPhotoCollisionsNeverOverwrite(folderName: String, returning: Bool) throws {
        let root = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(folderName)
        let sibling = root.appendingPathComponent(folderName == "Picks" ? "Rejects" : "Picks")
        for directory in [folder, sibling] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let photo = folder.appendingPathComponent("x.cr3")
        let target = (returning ? root : sibling).appendingPathComponent("x.cr3")
        try Data("source".utf8).write(to: photo)
        try Data("destination".utf8).write(to: target)
        try Data("metadata".utf8).write(to: folder.appendingPathComponent("x.xmp"))
        let decision: Decision = returning ? .undecided : folderName == "Picks" ? .reject : .pick
        var progressCalls = 0

        do {
            _ = try FileMover.moveFiles(items: [PhotoItem(url: photo, decision: decision)], folderURL: folder) { _, _ in
                progressCalls += 1
            }
            Issue.record("expected photo collision")
        } catch FileMover.MoveError.moveFailed(let file, _) {
            #expect(file == "x.cr3")
        }
        #expect(try Data(contentsOf: photo) == Data("source".utf8))
        #expect(try Data(contentsOf: target) == Data("destination".utf8))
        #expect(exists(folder, "x.xmp"))
        #expect(progressCalls == 0)
    }

    @Test(arguments: ["Picks", "Rejects"], [false, true])
    func sortedSidecarCollisionsKeepCompletedPhotoMove(folderName: String, returning: Bool) throws {
        let root = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(folderName)
        let sibling = root.appendingPathComponent(folderName == "Picks" ? "Rejects" : "Picks")
        for directory in [folder, sibling] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let target = returning ? root : sibling
        try Data().write(to: folder.appendingPathComponent("x.cr3"))
        try Data("source metadata".utf8).write(to: folder.appendingPathComponent("x.xmp"))
        try Data("destination metadata".utf8).write(to: target.appendingPathComponent("x.xmp"))
        let decision: Decision = returning ? .undecided : folderName == "Picks" ? .reject : .pick

        do {
            _ = try FileMover.moveFiles(
                items: [PhotoItem(url: folder.appendingPathComponent("x.cr3"), decision: decision)], folderURL: folder
            ) { _, _ in }
            Issue.record("expected sidecar collision")
        } catch FileMover.MoveError.moveFailed(let file, _) {
            #expect(file == "x.xmp")
        }
        #expect(exists(target, "x.cr3"))
        #expect(!exists(folder, "x.cr3"))
        #expect(try Data(contentsOf: folder.appendingPathComponent("x.xmp")) == Data("source metadata".utf8))
        #expect(try Data(contentsOf: target.appendingPathComponent("x.xmp")) == Data("destination metadata".utf8))
    }

    @Test(arguments: ["Picks", "Rejects"])
    func matchingSortedPhotosStayAndDoNotCreateNestedFolders(folderName: String) throws {
        let root = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let photo = folder.appendingPathComponent("x.jpg")
        try Data().write(to: photo)
        let items = [PhotoItem(url: photo, decision: folderName == "Picks" ? .pick : .reject)]
        let result = try FileMover.moveFiles(items: items, folderURL: folder) { _, _ in
            Issue.record("a photo staying in place must not advance progress")
        }
        #expect(result.totalMoved == 0)
        #expect(FileMover.moveCount(items: items, folderURL: folder) == 0)
        #expect(exists(folder, "x.jpg"))
        #expect(FolderScanner.folderTree(rootURL: folder).children.isEmpty)
    }

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

        #expect(totals == SessionTotals(folders: 3, picks: 2, rejects: 1, undecided: 2, filesToMove: 3))
    }

    @Test func sessionTotalsUseFolderDefaultsAndCountOnlyActualMoves() throws {
        let root = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Picks", "Rejects", "Album", "NoSession/Picks"] {
            let folder = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in ["a.png", "b.png", "c.png", "d.png"] {
                try Data().write(to: folder.appendingPathComponent(file))
            }
            if name != "NoSession/Picks" {
                try writeSession(in: folder, decisions: [
                    "a.png": .pick, "b.png": .reject, "c.png": .undecided, "missing.png": .pick
                ])
            }
        }

        #expect(FileMover.sessionTotals(rootURL: root) == SessionTotals(
            folders: 3, picks: 4, rejects: 4, undecided: 4, filesToMove: 6
        ))
        #expect(FileMover.sessionTotals(rootURL: root.appendingPathComponent("Picks")) == SessionTotals(
            folders: 1, picks: 2, rejects: 1, undecided: 1, filesToMove: 2
        ))
    }

    @Test func treeMovesSortedSessionsByDestinationWithoutReprocessingIncomingPhotos() throws {
        let root = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Picks", "Rejects"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        for path in ["root.png", "Picks/keep.png", "Picks/reject.cr3", "Picks/reject.xmp",
                     "Picks/return.cr3", "Picks/return.xmp", "Rejects/keep.png", "Rejects/pick.png",
                     "Rejects/return.png"] {
            try Data(path.utf8).write(to: root.appendingPathComponent(path))
        }
        try writeSession(in: root, decisions: ["root.png": .pick])
        try writeSession(in: root.appendingPathComponent("Picks"), decisions: [
            "reject.cr3": .reject, "return.cr3": .undecided,
            // A stale entry must not be applied to a photo arriving during this batch.
            "root.png": .reject
        ])
        try writeSession(in: root.appendingPathComponent("Rejects"), decisions: [
            "pick.png": .pick, "return.png": .undecided, "reject.cr3": .pick
        ])
        #expect(FileMover.sessionTotals(rootURL: root).filesToMove == 5)
        var updates: [Int] = []

        let result = try FileMover.moveAllSessions(rootURL: root) { completed, total in
            #expect(total == 5)
            updates.append(completed)
        }

        #expect(result == TreeMoveResult(folders: 3, picks: 2, rejects: 1, returnedToParent: 2))
        #expect(updates == [1, 2, 3, 4, 5])
        for path in ["Picks/root.png", "Picks/keep.png", "Picks/pick.png", "Rejects/keep.png",
                     "Rejects/reject.cr3", "Rejects/reject.xmp", "return.cr3", "return.xmp", "return.png"] {
            #expect(exists(root, path))
        }
        for path in ["root.png", "Picks/reject.cr3", "Picks/reject.xmp", "Picks/return.cr3",
                     "Picks/return.xmp", "Rejects/pick.png", "Rejects/return.png", ".rawcull-session.json",
                     "Picks/.rawcull-session.json", "Rejects/.rawcull-session.json",
                     "Picks/Picks", "Picks/Rejects", "Rejects/Picks", "Rejects/Rejects"] {
            #expect(!exists(root, path))
        }
    }

    @Test(arguments: ["Picks", "Rejects"])
    func treeMovesUndecidedOnlySortedSessionsIncludingASortedRoot(folderName: String) throws {
        let root = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("x.png"))
        try writeSession(in: folder, decisions: ["x.png": .undecided])
        #expect(FileMover.sessionTotals(rootURL: folder) == SessionTotals(
            folders: 1, picks: 0, rejects: 0, undecided: 1, filesToMove: 1
        ))

        let result = try FileMover.moveAllSessions(rootURL: folder) { completed, total in
            #expect(completed == 1 && total == 1)
        }

        #expect(result == TreeMoveResult(folders: 1, picks: 0, rejects: 0, returnedToParent: 1))
        #expect(exists(root, "x.png"))
        #expect(!exists(folder, "x.png"))
        #expect(!exists(folder, SavedSession.filename))
        #expect(FolderScanner.folderTree(rootURL: folder).children.isEmpty)
    }

    @Test func treeSkipsSortedFoldersWithoutSessionsAndWithoutMoves() throws {
        let root = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Picks", "Rejects"] {
            let folder = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data().write(to: folder.appendingPathComponent("x.png"))
        }
        // An empty saved decision dictionary still defaults the existing photo to pick.
        try writeSession(in: root.appendingPathComponent("Picks"), decisions: [:])
        #expect(FileMover.sessionTotals(rootURL: root) == SessionTotals(
            folders: 1, picks: 1, rejects: 0, undecided: 0, filesToMove: 0
        ))
        let result = try FileMover.moveAllSessions(rootURL: root) { _, _ in
            Issue.record("no photos should move")
        }
        #expect(result == TreeMoveResult(folders: 0, picks: 0, rejects: 0, returnedToParent: 0))
        #expect(exists(root, "Picks/x.png"))
        #expect(exists(root, "Rejects/x.png"))
        #expect(exists(root, "Picks/.rawcull-session.json"))
        #expect(!exists(root, "Picks/Picks"))
    }

    @Test(arguments: [false, true])
    func treeSortedCollisionsKeepSessionAndNameTheFolder(returning: Bool) throws {
        let root = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Picks", "Rejects"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let picks = root.appendingPathComponent("Picks")
        let target = returning ? root : root.appendingPathComponent("Rejects")
        try Data("source".utf8).write(to: picks.appendingPathComponent("x.png"))
        try Data("destination".utf8).write(to: target.appendingPathComponent("x.png"))
        try writeSession(in: picks, decisions: ["x.png": returning ? .undecided : .reject])

        do {
            _ = try FileMover.moveAllSessions(rootURL: root) { _, _ in }
            Issue.record("expected tree collision")
        } catch FileMover.MoveError.moveFailed(let file, _) {
            #expect(file == "Picks/x.png")
        }

        #expect(exists(picks, SavedSession.filename))
        #expect(try Data(contentsOf: picks.appendingPathComponent("x.png")) == Data("source".utf8))
        #expect(try Data(contentsOf: target.appendingPathComponent("x.png")) == Data("destination".utf8))
    }

    @Test func moveAllSessionsMovesEachFolderIntoItsOwnSubfolders() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        var lastProgress: (Int, Int) = (0, 0)
        let result = try FileMover.moveAllSessions(rootURL: root) { completed, total in
            lastProgress = (completed, total)
        }

        #expect(result == TreeMoveResult(folders: 2, picks: 2, rejects: 1, returnedToParent: 0))
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

        #expect(result == TreeMoveResult(folders: 2, picks: 1, rejects: 1, returnedToParent: 0))
        #expect(!exists(root, "A/Picks/a1.png"))
        #expect(exists(root, "A/Rejects/a2.png"))
    }

    @Test func moveAllSessionsIncludesTheRootFolderItself() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        FileManager.default.createFile(atPath: root.appendingPathComponent("r1.png").path, contents: Data())
        try writeSession(in: root, decisions: ["r1.png": .pick])

        #expect(FileMover.sessionTotals(rootURL: root) == SessionTotals(folders: 4, picks: 3, rejects: 1, undecided: 2, filesToMove: 4))

        let result = try FileMover.moveAllSessions(rootURL: root) { _, _ in }

        #expect(result == TreeMoveResult(folders: 3, picks: 3, rejects: 1, returnedToParent: 0))
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
