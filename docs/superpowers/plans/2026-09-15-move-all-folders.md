# Move All Folders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Move All Folders" action to the summary screen that moves every decided photo under the root folder into each folder's own `Picks/` and `Rejects/`.

**Architecture:** `SavedSession` becomes a shared model so `FileMover` can read session files. `FileMover` gains `sessionTotals(rootURL:)` and `moveAllSessions(rootURL:progress:)`, which walk `FolderScanner.folderTree` and reuse the existing per-folder `moveFiles`. `SummaryView` shows the tree-wide totals and the new button; `ContentView` passes the root URL down.

**Tech Stack:** Swift 6, SwiftUI (macOS 14+), Foundation, swift-testing. `swift build`, `swift test`.

**Spec:** `docs/superpowers/specs/2026-09-15-move-all-folders-design.md`

## Global Constraints

- Swift 6 toolchain, Swift Package, macOS 14+. Tests use swift-testing (`@Test`, `#expect`).
- Never use em dashes in code comments, UI copy, or docs.
- `.rawcull-session.json` format must not change: fields `version`, `currentIndex`, `decisions` keyed by filename.
- Every folder moves into its own `Picks/` and `Rejects/`; never into the root's.
- Commit after each task; commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

---

### Task 1: Extract `SavedSession` into its own model file

**Files:**
- Create: `Sources/RawCull/Models/SavedSession.swift`
- Modify: `Sources/RawCull/Models/CullSession.swift`
- Test: existing `Tests/RawCullTests/CullSessionTests.swift` (no new tests; behaviour is unchanged)

**Interfaces:**
- Produces: `struct SavedSession: Codable { let version: Int; let currentIndex: Int; let decisions: [String: Decision]; static let filename: String; static func url(in folderURL: URL) -> URL; static func load(from folderURL: URL) -> SavedSession? }`

- [ ] **Step 1: Create the model file**

Create `Sources/RawCull/Models/SavedSession.swift`:

```swift
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
```

- [ ] **Step 2: Use it from `CullSession`**

In `Sources/RawCull/Models/CullSession.swift`:

Delete the `// MARK: - Saved Session Format` comment and the `private struct SavedSession` at the bottom of the file.

In `load(folderURL:fileURLs:)`, replace

```swift
        // Check for existing session
        let sessionURL = folderURL.appendingPathComponent(".rawcull-session.json")
        if let data = try? Data(contentsOf: sessionURL),
           let saved = try? JSONDecoder().decode(SavedSession.self, from: data) {
```

with

```swift
        // Check for existing session
        if let saved = SavedSession.load(from: folderURL) {
```

In `saveSession()` and `deleteSessionFile()`, replace

```swift
        let sessionURL = folderURL.appendingPathComponent(".rawcull-session.json")
```

with

```swift
        let sessionURL = SavedSession.url(in: folderURL)
```

(two occurrences). Do not change anything else in the file.

- [ ] **Step 3: Build and run the existing tests**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!` with no warnings, and all 12 tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/RawCull/Models/SavedSession.swift Sources/RawCull/Models/CullSession.swift
git commit -m "Extract SavedSession into a shared model

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `FileMover.sessionTotals` and `FileMover.moveAllSessions`

**Files:**
- Modify: `Sources/RawCull/Services/FileMover.swift`
- Create: `Tests/RawCullTests/FileMoverTests.swift`

**Interfaces:**
- Consumes: `SavedSession.load(from:)`, `SavedSession.url(in:)` (Task 1); `FolderScanner.scan(folderURL:)`, `FolderScanner.folderTree(rootURL:)`, `FolderNode`; existing `FileMover.moveFiles(items:folderURL:progress:)`; `PhotoItem(url:decision:)`.
- Produces:
  - `struct SessionTotals: Equatable { let folders: Int; let picks: Int; let rejects: Int; let undecided: Int }`
  - `struct TreeMoveResult: Equatable { let folders: Int; let picks: Int; let rejects: Int }`
  - `static func FileMover.sessionTotals(rootURL: URL) -> SessionTotals`
  - `static func FileMover.moveAllSessions(rootURL: URL, progress: @escaping (Int, Int) -> Void) throws -> TreeMoveResult`

- [ ] **Step 1: Write the failing tests**

Create `Tests/RawCullTests/FileMoverTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FileMoverTests 2>&1 | tail -20`
Expected: compile error, `cannot find 'SessionTotals' in scope` / `type 'FileMover' has no member 'sessionTotals'`.

- [ ] **Step 3: Implement**

In `Sources/RawCull/Services/FileMover.swift`, add these two structs above `struct FileMover`:

```swift
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
```

Then add inside `struct FileMover`, after `moveFiles(...)`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -5`
Expected: all tests pass (12 existing + 3 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/RawCull/Services/FileMover.swift Tests/RawCullTests/FileMoverTests.swift
git commit -m "Add FileMover.sessionTotals and moveAllSessions

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Summary screen, wiring, README

**Files:**
- Modify: `Sources/RawCull/Views/SummaryView.swift`
- Modify: `Sources/RawCull/App/ContentView.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `FileMover.sessionTotals(rootURL:)`, `FileMover.moveAllSessions(rootURL:progress:)`, `SessionTotals`, `TreeMoveResult` (Task 2); `CullSession.flushSave()`, `deleteSessionFile()`, `folderURL`, counts.
- Produces: `SummaryView(onGoBack:onComplete:isContinuing:rootURL:)`.

- [ ] **Step 1: Update `SummaryView`**

Add the property after `let isContinuing: Bool`:

```swift
    let rootURL: URL?
```

Add state after `@State private var resultMessage = ""`:

```swift
    @State private var totals: SessionTotals?
```

Insert this block directly after the `if session.undecidedCount > 0 { ... }` block (still inside the `else` branch, before `if isMoving`):

```swift
                if let rootURL {
                    VStack(spacing: 8) {
                        Text("All folders under \(rootURL.lastPathComponent)")
                            .font(.headline)
                        if let totals {
                            SummaryRow(label: "Folders with decisions", count: totals.folders, color: .secondary, icon: "folder")
                            SummaryRow(label: "Picks", count: totals.picks, color: .green, icon: "checkmark.circle.fill")
                            SummaryRow(label: "Rejects", count: totals.rejects, color: .red, icon: "xmark.circle.fill")
                            SummaryRow(label: "Undecided", count: totals.undecided, color: .secondary, icon: "questionmark.circle")
                        } else {
                            ProgressView("Counting folders...")
                                .controlSize(.small)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary))
                }
```

Replace the `HStack(spacing: 16) { Go Back / Move Files }` with:

```swift
                    HStack(spacing: 16) {
                        Button("Go Back") {
                            onGoBack()
                        }
                        .controlSize(.large)

                        Button("Move Files") {
                            moveFiles()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(session.pickCount + session.rejectCount == 0)

                        if rootURL != nil {
                            Button("Move All Folders") {
                                moveAllFolders()
                            }
                            .controlSize(.large)
                            .disabled((totals?.picks ?? 0) + (totals?.rejects ?? 0) == 0)
                        }
                    }
```

Add a task modifier after `.padding(40)` at the end of `body`:

```swift
        .task(id: rootURL) {
            guard let rootURL else { return }
            // Flush first so the folder being reviewed is counted from disk.
            session.flushSave()
            let computed = await Task.detached(priority: .userInitiated) {
                FileMover.sessionTotals(rootURL: rootURL)
            }.value
            totals = computed
        }
```

Add this method after `moveFiles()`:

```swift
    private func moveAllFolders() {
        guard let rootURL else { return }
        session.flushSave()
        isMoving = true
        moveError = nil

        Task {
            do {
                let result = try FileMover.moveAllSessions(rootURL: rootURL) { completed, total in
                    Task { @MainActor in
                        moveProgress = total == 0 ? 1 : Double(completed) / Double(total)
                    }
                }

                // The current folder's file is already gone; this clears any
                // pending debounced save so it cannot come back.
                session.deleteSessionFile()

                await MainActor.run {
                    isMoving = false
                    moveComplete = true
                    resultMessage = "\(result.picks) picks and \(result.rejects) rejects moved across \(result.folders) folders"
                }
            } catch {
                await MainActor.run {
                    isMoving = false
                    moveError = error.localizedDescription
                }
            }
        }
    }
```

- [ ] **Step 2: Pass the root from `ContentView`**

In `Sources/RawCull/App/ContentView.swift`, change the `SummaryView(...)` call to:

```swift
                SummaryView(
                    onGoBack: { appState = .culling },
                    onComplete: continueAfterMove,
                    isContinuing: isContinuing,
                    rootURL: rootURL
                )
```

- [ ] **Step 3: README**

In `README.md`, under `# How It Works`, replace step 7:

```
7. On the summary screen, press `Move Files` to move accepted photos into `Picks/` and rejected photos into `Rejects/`, then `Continue` to go back to the tree.
```

with:

```
7. On the summary screen, press `Move Files` to move this folder's accepted photos into `Picks/` and rejected photos into `Rejects/`. Press `Move All Folders` to do the same for every folder under the root that has saved decisions, each into its own `Picks/` and `Rejects/`. Then press `Continue` to go back to the tree.
```

- [ ] **Step 4: Build and test**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!` with no warnings, all 15 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/RawCull/Views/SummaryView.swift Sources/RawCull/App/ContentView.swift README.md
git commit -m "Add Move All Folders to the summary screen

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
