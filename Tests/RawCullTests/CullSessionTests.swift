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

    private func makeSelectionSession(count: Int = 8) -> CullSession {
        let session = CullSession()
        // No decisions are written by selection or navigation.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        session.load(folderURL: folder, fileURLs: (0..<count).map {
            folder.appendingPathComponent("\($0).png")
        })
        return session
    }

    private func selectedIndices(_ session: CullSession) -> [Int] {
        session.items.indices.filter { session.isSelected(index: $0) }
    }

    @Test func plainClickReplacesSelectionAndSetsCurrentAndAnchor() {
        let session = makeSelectionSession()
        #expect(selectedIndices(session) == [0])
        session.select(index: 4, extendingRange: true)
        session.select(index: 2)
        #expect(selectedIndices(session) == [2])
        #expect(session.currentIndex == 2)
        #expect(session.selectionAnchorIndex == 2)
        #expect(session.actionTargets.map(\.id) == [session.items[2].id])
    }

    @Test func shiftRangeReplacesSelectionInBothDirectionsAndKeepsAnchor() {
        let session = makeSelectionSession()
        session.select(index: 3)
        session.select(index: 6, extendingRange: true)
        #expect(selectedIndices(session) == [3, 4, 5, 6])
        #expect(session.currentIndex == 6)
        #expect(session.selectionAnchorIndex == 3)

        // Shift wins even when a toggle modifier is also held.
        session.select(index: 1, extendingRange: true, toggling: true)
        #expect(selectedIndices(session) == [1, 2, 3])
        #expect(session.currentIndex == 1)
        #expect(session.selectionAnchorIndex == 3)
        session.select(index: 3, extendingRange: true)
        #expect(selectedIndices(session) == [3])
    }

    @Test func toggleAddsAndRemovesNonCurrentItemsAndResetsAnchor() {
        let session = makeSelectionSession()
        session.select(index: 5, toggling: true)
        #expect(selectedIndices(session) == [0, 5])
        #expect(session.currentIndex == 5)
        #expect(session.selectionAnchorIndex == 5)
        session.select(index: 0, toggling: true)
        #expect(selectedIndices(session) == [5])
        #expect(session.currentIndex == 5)
        #expect(session.selectionAnchorIndex == 5)
        session.select(index: 3, extendingRange: true)
        #expect(selectedIndices(session) == [3, 4, 5])
        session.select(index: 4, toggling: true)
        #expect(selectedIndices(session) == [3, 5])
        #expect(session.currentIndex == 3)
        #expect(session.selectionAnchorIndex == 3)
    }

    @Test(arguments: [([2, 6], 2), ([0, 5], 5), ([3, 7], 3)])
    func removingCurrentChoosesNearestRemainingIndexWithLowerTieWinner(
        remaining: [Int], expected: Int
    ) {
        let session = makeSelectionSession()
        session.select(index: remaining[0])
        session.select(index: remaining[1], toggling: true)
        session.select(index: 4, toggling: true)
        session.select(index: 4, toggling: true)
        #expect(selectedIndices(session) == remaining)
        #expect(session.currentIndex == expected)
        #expect(session.selectionAnchorIndex == expected)
        #expect(session.isSelected(index: session.currentIndex))
    }

    @Test func togglingTheOnlySelectedItemDoesNothing() {
        let session = makeSelectionSession()
        session.select(index: 3)
        session.select(index: 3, toggling: true)
        #expect(selectedIndices(session) == [3])
        #expect(session.currentIndex == 3)
        #expect(session.selectionAnchorIndex == 3)
    }

    @Test func navigationAndJumpCollapseSelectionIncludingAtTheEdges() {
        let session = makeSelectionSession()
        session.select(index: 2, extendingRange: true)
        session.next()
        #expect(selectedIndices(session) == [3])
        #expect(session.selectionAnchorIndex == 3)
        session.select(index: 5, extendingRange: true)
        session.previous()
        #expect(selectedIndices(session) == [4])
        #expect(session.selectionAnchorIndex == 4)
        session.select(index: 6, extendingRange: true)
        session.jumpTo(index: 6)
        #expect(selectedIndices(session) == [6])
        #expect(session.selectionAnchorIndex == 6)

        session.select(index: 0)
        session.select(index: 2, toggling: true)
        session.select(index: 0, toggling: true)
        session.select(index: 0, toggling: true)
        session.previous()
        #expect(selectedIndices(session) == [0])
        #expect(session.selectionAnchorIndex == 0)
        session.select(index: 7, toggling: true)
        session.next()
        #expect(selectedIndices(session) == [7])
        #expect(session.selectionAnchorIndex == 7)
    }

    @Test func loadResumesCurrentAsSingleSelectionAndResetClearsIt() throws {
        let folder = try makeFolder(files: ["a.png", "b.png", "c.png"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let saved = SavedSession(version: 1, currentIndex: 1, decisions: [:])
        try JSONEncoder().encode(saved).write(to: SavedSession.url(in: folder))
        let session = makeSelectionSession()
        session.select(index: 5, extendingRange: true)
        session.load(folderURL: folder, fileURLs: FolderScanner.scan(folderURL: folder))
        #expect(selectedIndices(session) == [1])
        #expect(session.selectionAnchorIndex == 1)
        session.select(index: 2, extendingRange: true)
        session.reset()
        #expect(session.selectedItemIDs.isEmpty)
        #expect(session.currentIndex == 0)
        #expect(session.selectionAnchorIndex == 0)
        #expect(session.actionTargets.isEmpty)

        session.load(folderURL: folder, fileURLs: [])
        #expect(session.selectionCount == 0)
        #expect(session.currentIndex == 0)
        session.next()
        session.previous()
        session.select(index: 0, extendingRange: true)
        #expect(!session.collapseSelection())
        #expect(session.contextMenuTargets(index: 0).isEmpty)
    }

    @Test func escapeCollapseIsConsumedOnlyForMultipleSelection() {
        let session = makeSelectionSession()
        #expect(!session.collapseSelection())
        session.select(index: 4, extendingRange: true)
        #expect(session.collapseSelection())
        #expect(selectedIndices(session) == [4])
        #expect(session.selectionAnchorIndex == 4)
        #expect(!session.collapseSelection())
    }

    @Test func contextTargetsRespectMembershipWithoutChangingSelectionOrCurrent() {
        let session = makeSelectionSession()
        session.select(index: 2, extendingRange: true)
        let ids = session.selectedItemIDs
        #expect(session.actionTargets.map(\.id) == Array(session.items[0...2]).map(\.id))
        #expect(session.contextMenuTargets(index: 0).map(\.id) == session.actionTargets.map(\.id))
        #expect(session.contextMenuTargets(index: 5).map(\.id) == [session.items[5].id])
        #expect(session.selectedItemIDs == ids)
        #expect(session.currentIndex == 2)
        #expect(session.selectionAnchorIndex == 0)
        session.jumpTo(index: 2)
        #expect(session.contextMenuTargets(index: 5).map(\.id) == [session.items[5].id])
        #expect(selectedIndices(session) == [2])
        #expect(!session.isSelected(index: -1))
        #expect(session.contextMenuTargets(index: 99).isEmpty)
        session.select(index: 99, extendingRange: true)
        session.jumpTo(index: -1)
        #expect(selectedIndices(session) == [2])
    }

    @Test func batchDecisionsUpdateMixedCountsAndWriteOncePerChangedAction() async throws {
        let folder = try makeFolder(files: ["a.png", "b.png", "c.png", "d.png"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let saved = SavedSession(version: 1, currentIndex: 0, decisions: ["a.png": .pick, "b.png": .reject])
        try JSONEncoder().encode(saved).write(to: SavedSession.url(in: folder))
        var writes: [SavedSession] = []
        let session = CullSession(writeSession: { saved, url in
            writes.append(saved)
            try JSONEncoder().encode(saved).write(to: url, options: .atomic)
        })
        session.load(folderURL: folder, fileURLs: FolderScanner.scan(folderURL: folder))
        session.select(index: 2, extendingRange: true)

        for decision in [Decision.pick, .reject, .undecided] {
            let previousWrites = writes.count
            switch decision {
            case .pick: session.markPick()
            case .reject: session.markReject()
            case .undecided: session.unmarkCurrent()
            }
            #expect(session.items.map(\.decision) == [decision, decision, decision, .undecided])
            #expect(session.pickCount == (decision == .pick ? 3 : 0))
            #expect(session.rejectCount == (decision == .reject ? 3 : 0))
            #expect(session.undecidedCount == (decision == .undecided ? 4 : 1))
            #expect(session.currentIndex == 2)
            #expect(selectedIndices(session) == [0, 1, 2])
            #expect(writes.count == previousWrites)
            session.flushSave()
            #expect(writes.count == previousWrites + 1)
            #expect(writes.last?.decisions == Dictionary(uniqueKeysWithValues: session.items.map { ($0.filename, $0.decision) }))

            // Repeating the same decision must not schedule another save.
            session.applyDecision(decision, to: session.actionTargets.map(\.id))
            session.flushSave()
            #expect(writes.count == previousWrites + 1)
        }
        try await Task.sleep(for: .seconds(1.2))
        #expect(writes.count == 3)
        #expect(try savedDecisions(in: folder)?.values.allSatisfy { $0 == "undecided" } == true)
    }

    @Test func contextDecisionOnlyChangesExplicitTargetsAndSingleActionsStayCurrentOnly() {
        let session = makeSelectionSession()
        session.select(index: 2, extendingRange: true)
        let targets = session.contextMenuTargets(index: 5)
        session.applyDecision(.pick, to: targets.map(\.id) + targets.map(\.id) + [UUID()])
        #expect(session.pickCount == 1)
        #expect(session.items[5].decision == .pick)
        #expect(session.currentIndex == 2)
        #expect(selectedIndices(session) == [0, 1, 2])
        session.jumpTo(index: 1)
        session.markReject()
        #expect(session.items[1].decision == .reject)
        #expect(session.pickCount == 1)
        #expect(session.rejectCount == 1)
        #expect(session.undecidedCount == 6)
        session.unmarkCurrent()
        #expect(session.rejectCount == 0)
        #expect(session.undecidedCount == 7)
        session.discardPendingSave()
    }

    @Test func batchDecisionDebouncesToOneCompleteAtomicWrite() async throws {
        let folder = try makeFolder(files: ["a.png", "b.png", "c.png"])
        defer { try? FileManager.default.removeItem(at: folder) }
        var writes = 0
        let session = CullSession(writeSession: { saved, url in
            writes += 1
            try JSONEncoder().encode(saved).write(to: url, options: .atomic)
        })
        session.load(folderURL: folder, fileURLs: FolderScanner.scan(folderURL: folder))
        session.select(index: 2, extendingRange: true)
        session.markPick()
        #expect(writes == 0)
        // Other MainActor tests can delay the debounce task's start.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while writes == 0 && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(writes == 1)
        #expect(try savedDecisions(in: folder) == ["a.png": "pick", "b.png": "pick", "c.png": "pick"])
        session.flushSave()
        #expect(writes == 1)
    }

    @Test(arguments: ["Picks", "Rejects", "picks", "rejects", "Album"])
    func folderDecisionIsTheDefaultWithoutASession(folderName: String) throws {
        let root = try makeFolder(files: [])
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["a.png", "b.png"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }

        let session = CullSession()
        session.load(folderURL: folder, fileURLs: FolderScanner.scan(folderURL: folder))

        let expected: Decision = folderName == "Picks" ? .pick : folderName == "Rejects" ? .reject : .undecided
        #expect(session.items.map(\.decision) == [expected, expected])
        #expect(session.pickCount == (expected == .pick ? 2 : 0))
        #expect(session.rejectCount == (expected == .reject ? 2 : 0))
        #expect(session.undecidedCount == (expected == .undecided ? 2 : 0))
        #expect(SavedSession.load(from: folder) == nil)
    }

    @Test(arguments: ["Picks", "Rejects"])
    func savedDecisionsOverrideTheSortedFolderDefault(folderName: String) throws {
        let root = try makeFolder(files: [])
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["a.png", "b.png", "c.png", "d.png"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        let saved = SavedSession(version: 1, currentIndex: 2, decisions: [
            "a.png": .pick, "b.png": .reject, "c.png": .undecided
        ])
        try JSONEncoder().encode(saved).write(to: SavedSession.url(in: folder))

        let session = CullSession()
        session.load(folderURL: folder, fileURLs: FolderScanner.scan(folderURL: folder))

        #expect(session.items.map(\.decision) == [.pick, .reject, .undecided, folderName == "Picks" ? .pick : .reject])
        #expect(session.currentIndex == 2)
        #expect(session.pickCount == (folderName == "Picks" ? 2 : 1))
        #expect(session.rejectCount == (folderName == "Rejects" ? 2 : 1))
        #expect(session.undecidedCount == 1)
    }

    @Test(arguments: ["Picks", "Rejects"])
    func sortedMoveDeletesSessionAndReloadsRemainingPhotos(folderName: String) throws {
        let root = try makeFolder(files: [])
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["a.png", "b.png", "c.png"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        let session = CullSession()
        session.load(folderURL: folder, fileURLs: FolderScanner.scan(folderURL: folder))
        if folderName == "Picks" { session.markReject() }
        else { session.markPick() }
        session.next()
        session.unmarkCurrent()
        session.flushSave()

        let result = try FileMover.moveFiles(items: session.items, folderURL: folder) { _, _ in }
        session.deleteSessionFile()
        session.load(folderURL: folder, fileURLs: FolderScanner.scan(folderURL: folder))

        #expect(result.totalMoved == 2)
        #expect(result.returnedToParent == 1)
        #expect(session.items.map(\.filename) == ["c.png"])
        #expect(session.items.first?.decision == (folderName == "Picks" ? .pick : .reject))
        #expect(SavedSession.load(from: folder) == nil)
        #expect(FolderScanner.folderTree(rootURL: root).children.map(\.name) == ["Picks", "Rejects"])
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
