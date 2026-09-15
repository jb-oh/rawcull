# Folder Tree Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a folder tree panel to the culling screen so a user opens one root folder and culls each subfolder in turn without returning to the welcome screen.

**Architecture:** The welcome screen's folder becomes the root. `ContentView` owns the root URL and a `FolderNode` tree, and swaps the `CullSession` to a different folder's top-level photos when a tree row is clicked. Each folder keeps its own `.rawcull-session.json` and `Picks/`/`Rejects/`, so the persistence model is unchanged. A `flushSave()` on the session prevents losing debounced decisions when switching folders or quitting.

**Tech Stack:** Swift 6, SwiftUI (macOS 14+), Foundation `FileManager`, swift-testing (`import Testing`). Build with `swift build`, test with `swift test`.

**Spec:** `docs/superpowers/specs/2026-09-15-folder-tree-panel-design.md`

## Global Constraints

- macOS 14 or newer, Swift 6 toolchain, Swift Package (no Xcode project).
- Tests use swift-testing (`@Test`, `#expect`), not XCTest.
- Never use em dashes in code comments, UI copy, or docs.
- Clicking a folder loads only files directly inside it (top level). Do not recurse into photos.
- `.rawcull-session.json` format must not change.
- Commit after each task. End commit messages with:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`

---

### Task 1: `FolderNode` model and `FolderScanner.folderTree`

**Files:**
- Create: `Sources/RawCull/Models/FolderNode.swift`
- Modify: `Sources/RawCull/Services/FolderScanner.swift` (add after `scan(folderURL:)`)
- Test: `Tests/RawCullTests/FolderScannerTests.swift`

**Interfaces:**
- Consumes: `FolderScanner` (existing static struct).
- Produces:
  - `struct FolderNode: Identifiable, Hashable { let url: URL; let name: String; let children: [FolderNode]; var id: URL; func first(where:) -> FolderNode? }`
  - `static func FolderScanner.folderTree(rootURL: URL) -> FolderNode`

- [ ] **Step 1: Write the failing tests**

Append inside `struct FolderScannerTests` in `Tests/RawCullTests/FolderScannerTests.swift`:

```swift
    @Test func folderTreeBuildsNestedFoldersInNaturalOrderSkippingHiddenAndFiles() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        for path in ["Day 10", "Day 2", "Day 2/Raw", "Day 2/Jpeg", ".hidden"] {
            try fileManager.createDirectory(
                at: tempDir.appendingPathComponent(path),
                withIntermediateDirectories: true
            )
        }
        fileManager.createFile(atPath: tempDir.appendingPathComponent("a.png").path, contents: Data())

        let tree = FolderScanner.folderTree(rootURL: tempDir)

        #expect(tree.url == tempDir)
        #expect(tree.name == tempDir.lastPathComponent)
        #expect(tree.children.map(\.name) == ["Day 2", "Day 10"])
        #expect(tree.children[0].children.map(\.name) == ["Jpeg", "Raw"])
        #expect(tree.children[1].children.isEmpty)
    }

    @Test func folderTreeDoesNotFollowSymbolicLinks() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        try fileManager.createDirectory(
            at: tempDir.appendingPathComponent("Real"),
            withIntermediateDirectories: true
        )
        // A link back to the root would recurse forever if followed.
        try fileManager.createSymbolicLink(
            at: tempDir.appendingPathComponent("Link"),
            withDestinationURL: tempDir
        )

        let tree = FolderScanner.folderTree(rootURL: tempDir)

        #expect(tree.children.map(\.name) == ["Real"])
    }

    @Test func folderNodeFirstWhereSearchesDepthFirst() throws {
        let leaf = FolderNode(url: URL(fileURLWithPath: "/r/a/b"), name: "b", children: [])
        let mid = FolderNode(url: URL(fileURLWithPath: "/r/a"), name: "a", children: [leaf])
        let root = FolderNode(url: URL(fileURLWithPath: "/r"), name: "r", children: [mid])

        #expect(root.first(where: { $0.name == "b" })?.url == leaf.url)
        #expect(root.first(where: { $0.name == "zzz" }) == nil)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FolderScannerTests 2>&1 | tail -20`
Expected: compile error, `cannot find 'FolderNode' in scope` / `type 'FolderScanner' has no member 'folderTree'`.

- [ ] **Step 3: Create the model**

Create `Sources/RawCull/Models/FolderNode.swift`:

```swift
import Foundation

/// One folder in the tree shown in the culling screen's folder panel.
struct FolderNode: Identifiable, Hashable {
    let url: URL
    let name: String
    let children: [FolderNode]

    var id: URL { url }

    /// Depth-first search over this node and its descendants.
    func first(where predicate: (FolderNode) -> Bool) -> FolderNode? {
        if predicate(self) { return self }
        for child in children {
            if let found = child.first(where: predicate) {
                return found
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Add `folderTree` to `FolderScanner`**

Insert after the closing brace of `scan(folderURL:)` in `Sources/RawCull/Services/FolderScanner.swift`:

```swift
    /// Builds the folder tree rooted at `rootURL`. Hidden folders are skipped
    /// and symbolic links are not followed, so a link back to an ancestor
    /// cannot cause infinite recursion. Children are naturally sorted.
    static func folderTree(rootURL: URL) -> FolderNode {
        FolderNode(
            url: rootURL,
            name: rootURL.lastPathComponent,
            children: subfolderNodes(of: rootURL)
        )
    }

    private static func subfolderNodes(of folderURL: URL) -> [FolderNode] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var nodes: [FolderNode] = []
        for url in contents {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true,
                  values.isDirectory == true else {
                continue
            }
            nodes.append(FolderNode(
                url: url,
                name: url.lastPathComponent,
                children: subfolderNodes(of: url)
            ))
        }

        nodes.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return nodes
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter FolderScannerTests 2>&1 | tail -20`
Expected: all `FolderScannerTests` pass, including the three new ones.

- [ ] **Step 6: Commit**

```bash
git add Sources/RawCull/Models/FolderNode.swift Sources/RawCull/Services/FolderScanner.swift Tests/RawCullTests/FolderScannerTests.swift
git commit -m "Add FolderNode and FolderScanner.folderTree

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `CullSession.flushSave()` and quit-time flush

**Files:**
- Modify: `Sources/RawCull/Models/CullSession.swift`
- Modify: `Sources/RawCull/App/ContentView.swift`
- Create: `Tests/RawCullTests/CullSessionTests.swift`

**Interfaces:**
- Consumes: `CullSession.load(folderURL:fileURLs:)`, `scheduleSave()`, `saveSession()`, `deleteSessionFile()`, `reset()` (existing).
- Produces: `func CullSession.flushSave()` (public, `@MainActor` via the class). `load(...)` now flushes the previous folder's pending save before replacing state.

Background: `applyDecision` calls `scheduleSave()`, which waits one second before writing `.rawcull-session.json`. Switching folders or quitting inside that window loses the last decision. We add a `hasPendingSave` flag so `flushSave()` writes only when something is actually pending. Writing unconditionally would create a session file in every folder the user merely visits, which would trigger the welcome screen's "Resume Session?" prompt later.

- [ ] **Step 1: Write the failing tests**

Create `Tests/RawCullTests/CullSessionTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CullSessionTests 2>&1 | tail -20`
Expected: compile error `value of type 'CullSession' has no member 'flushSave'`.

- [ ] **Step 3: Implement `flushSave` and the pending flag**

In `Sources/RawCull/Models/CullSession.swift`:

Add a field next to `saveTask`:

```swift
    private var saveTask: Task<Void, Never>?
    @ObservationIgnored
    private var hasPendingSave = false
```

Change the start of `load(folderURL:fileURLs:)` so the previous folder is flushed first:

```swift
    func load(folderURL: URL, fileURLs: [URL]) {
        flushSave()
        self.folderURL = folderURL
```

Change `reset()` to clear the flag:

```swift
    func reset() {
        saveTask?.cancel()
        saveTask = nil
        hasPendingSave = false
        items = []
        currentIndex = 0
        pickCount = 0
        rejectCount = 0
        undecidedCount = 0
        folderURL = nil
        isLoaded = false
    }
```

Replace `scheduleSave()` and `saveSession()` and add `flushSave()`:

```swift
    /// Writes any pending decisions to disk right away. Call before switching
    /// folders, closing the folder, or quitting, so the one second debounce
    /// in `scheduleSave()` cannot drop the last decision.
    func flushSave() {
        guard hasPendingSave else { return }
        saveTask?.cancel()
        saveTask = nil
        saveSession()
    }

    private func scheduleSave() {
        hasPendingSave = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveSession()
        }
    }

    private func saveSession() {
        guard let folderURL else { return }
        hasPendingSave = false
        let sessionURL = folderURL.appendingPathComponent(".rawcull-session.json")
        var decisions: [String: Decision] = [:]
        for item in items {
            decisions[item.filename] = item.decision
        }
        let saved = SavedSession(
            version: 1,
            currentIndex: currentIndex,
            decisions: decisions
        )
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: sessionURL, options: .atomic)
        }
    }
```

Change `deleteSessionFile()` so a pending save cannot recreate the file after the move:

```swift
    func deleteSessionFile() {
        saveTask?.cancel()
        saveTask = nil
        hasPendingSave = false
        guard let folderURL else { return }
        let sessionURL = folderURL.appendingPathComponent(".rawcull-session.json")
        try? FileManager.default.removeItem(at: sessionURL)
    }
```

- [ ] **Step 4: Flush on quit**

In `Sources/RawCull/App/ContentView.swift`, add `import AppKit` at the top and attach a receiver after `.frame(minWidth: 800, minHeight: 600)`:

```swift
        .frame(minWidth: 800, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            session.flushSave()
        }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -20`
Expected: all tests pass, including the four `CullSessionTests`.

- [ ] **Step 6: Commit**

```bash
git add Sources/RawCull/Models/CullSession.swift Sources/RawCull/App/ContentView.swift Tests/RawCullTests/CullSessionTests.swift
git commit -m "Add CullSession.flushSave and flush on folder change and quit

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Empty folder state in the culling screen

**Files:**
- Modify: `Sources/RawCull/Views/StatusBar.swift`
- Modify: `Sources/RawCull/Views/CullingView.swift`

**Interfaces:**
- Consumes: `CullSession.count`, `CullSession.currentItem` (existing).
- Produces: `CullingView` renders a placeholder when `session.count == 0`, `Finish` is disabled then, `StatusBar` shows `0 / 0`.

Background: `PhotoView` shows a spinner whenever `image` is nil, which is also what an empty folder produces. Once a tree lets the user pick any folder, empty folders become a normal case and need a real empty state.

- [ ] **Step 1: Fix the counter in `StatusBar`**

In `Sources/RawCull/Views/StatusBar.swift` replace:

```swift
                Text("\(currentIndex + 1) / \(totalCount)")
```

with:

```swift
                Text(totalCount == 0 ? "0 / 0" : "\(currentIndex + 1) / \(totalCount)")
```

- [ ] **Step 2: Add the empty state to `CullingView`**

In `Sources/RawCull/Views/CullingView.swift`, replace the `PhotoView(...)` call inside the main `VStack` with:

```swift
                // Photo
                if session.count == 0 {
                    EmptyFolderView()
                } else {
                    PhotoView(
                        image: currentPreview,
                        decision: session.currentItem?.decision ?? .undecided,
                        isZoomed: $isZoomed,
                        rotationQuarterTurns: rotationQuarterTurns
                    )
                }
```

Change the `Finish` toolbar button:

```swift
            ToolbarItem(placement: .primaryAction) {
                Button("Finish") {
                    onFinish()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(session.count == 0)
            }
```

Add at the bottom of the file, above `private struct WindowFocusActivator`:

```swift
private struct EmptyFolderView: View {
    var body: some View {
        ZStack {
            Color.black
            ContentUnavailableView(
                "No photos in this folder",
                systemImage: "photo",
                description: Text("Pick another folder from the tree on the left.")
            )
            .foregroundStyle(.white)
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` with no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/RawCull/Views/StatusBar.swift Sources/RawCull/Views/CullingView.swift
git commit -m "Show an empty state for folders without photos

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: `FolderTreePanel` view

**Files:**
- Create: `Sources/RawCull/Views/FolderTreePanel.swift`

**Interfaces:**
- Consumes: `FolderNode` (Task 1: `url`, `name`, `children`, `first(where:)`).
- Produces: `struct FolderTreePanel: View { init(root: FolderNode, selectedURL: URL?, onSelect: @escaping (URL) -> Void) }`

Design notes:
- Recursive `DisclosureGroup` rows instead of `OutlineGroup`, because `OutlineGroup` gives no control over expansion and we want the root expanded on first show.
- Selection is derived from `selectedURL` by path comparison, not `URL ==`. `URL` equality is sensitive to a trailing slash, and the session's folder URL may come from `NSOpenPanel` while tree URLs come from `contentsOfDirectory`.
- Keyboard arrows are consumed by `CullingView`'s local key monitor before the `List` sees them, so list keyboard navigation does not fight the culling shortcuts.

- [ ] **Step 1: Create the view**

Create `Sources/RawCull/Views/FolderTreePanel.swift`:

```swift
import SwiftUI

/// Sidebar tree of the root folder and its subfolders. Selecting a row asks
/// the owner to switch the culling session to that folder.
struct FolderTreePanel: View {
    let root: FolderNode
    let selectedURL: URL?
    let onSelect: (URL) -> Void

    @State private var expandedURLs: Set<URL> = []

    var body: some View {
        List(selection: selectionBinding) {
            FolderTreeRow(node: root, expandedURLs: $expandedURLs)
        }
        .listStyle(.sidebar)
        .onAppear {
            expandedURLs.insert(root.url)
        }
        .onChange(of: root) { _, newRoot in
            expandedURLs.insert(newRoot.url)
        }
    }

    /// Maps the session's folder URL onto the matching tree node by path, and
    /// forwards row clicks to `onSelect`.
    private var selectionBinding: Binding<URL?> {
        Binding(
            get: {
                guard let selectedPath = selectedURL?.path else { return nil }
                return root.first(where: { $0.url.path == selectedPath })?.url
            },
            set: { newValue in
                if let newValue {
                    onSelect(newValue)
                }
            }
        )
    }
}

private struct FolderTreeRow: View {
    let node: FolderNode
    @Binding var expandedURLs: Set<URL>

    var body: some View {
        if node.children.isEmpty {
            label
        } else {
            DisclosureGroup(isExpanded: expansionBinding) {
                ForEach(node.children) { child in
                    FolderTreeRow(node: child, expandedURLs: $expandedURLs)
                }
            } label: {
                label
            }
            .tag(node.url)
        }
    }

    private var label: some View {
        Label(node.name, systemImage: "folder")
            .lineLimit(1)
            .truncationMode(.middle)
            .tag(node.url)
    }

    private var expansionBinding: Binding<Bool> {
        Binding(
            get: { expandedURLs.contains(node.url) },
            set: { isExpanded in
                if isExpanded {
                    expandedURLs.insert(node.url)
                } else {
                    expandedURLs.remove(node.url)
                }
            }
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`. The view is not yet used; that is fine.

- [ ] **Step 3: Commit**

```bash
git add Sources/RawCull/Views/FolderTreePanel.swift
git commit -m "Add FolderTreePanel view

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Wire the tree into the app flow

**Files:**
- Modify: `Sources/RawCull/App/ContentView.swift`
- Modify: `Sources/RawCull/Views/CullingView.swift`
- Modify: `Sources/RawCull/Views/SummaryView.swift`

**Interfaces:**
- Consumes: `FolderScanner.folderTree(rootURL:)` and `FolderScanner.scan(folderURL:)`, `FolderNode`, `FolderTreePanel(root:selectedURL:onSelect:)`, `CullSession.flushSave()` / `load` / `reset()` / `folderURL` / `count`, `ImageLoader.clearAll()` / `startLoading(items:currentIndex:)`.
- Produces: `CullingView(folderTree: FolderNode?, onSelectFolder: @escaping (URL) -> Void, onFinish: @escaping () -> Void, onCloseFolder: @escaping () -> Void)`.

Flow summary (from the spec):
- Welcome folder becomes `rootURL`; tree is built in the background.
- Clicking a row: ignore if same folder, cancel any in-flight switch, scan on a background task, then `clearAll` → `load` → `startLoading`. `load` flushes the previous folder's pending save itself (Task 2).
- After Move Files, "Continue" returns to culling, rescans the current folder and rebuilds the tree.
- "Close Folder" flushes, resets, clears root and tree, returns to welcome.

- [ ] **Step 1: Rewrite `ContentView`**

Replace the whole of `Sources/RawCull/App/ContentView.swift` with:

```swift
import AppKit
import SwiftUI

enum AppState {
    case welcome
    case culling
    case done
}

struct ContentView: View {
    @Environment(CullSession.self) private var session
    @State private var appState: AppState = .welcome
    @State private var imageLoader = ImageLoader()
    @State private var rootURL: URL?
    @State private var folderTree: FolderNode?
    @State private var switchTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch appState {
            case .welcome:
                WelcomeView(onFolderSelected: startCulling)
            case .culling:
                CullingView(
                    folderTree: folderTree,
                    onSelectFolder: switchFolder,
                    onFinish: { appState = .done },
                    onCloseFolder: closeFolder
                )
                .environment(imageLoader)
            case .done:
                SummaryView(
                    onGoBack: { appState = .culling },
                    onComplete: continueAfterMove
                )
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            session.flushSave()
        }
    }

    // MARK: - Flow

    private func startCulling(folderURL: URL, fileURLs: [URL]) {
        rootURL = folderURL
        session.load(folderURL: folderURL, fileURLs: fileURLs)
        imageLoader.startLoading(items: session.items, currentIndex: session.currentIndex)
        appState = .culling
        rebuildTree()
    }

    /// Switches the session to `url` (top-level photos only). Ignores a click
    /// on the folder that is already loaded. A newer click cancels an older
    /// in-flight switch so only the last selection wins.
    private func switchFolder(_ url: URL) {
        guard url.path != session.folderURL?.path else { return }
        loadFolder(url)
    }

    private func loadFolder(_ url: URL) {
        switchTask?.cancel()
        switchTask = Task {
            let fileURLs = await Task.detached(priority: .userInitiated) {
                FolderScanner.scan(folderURL: url)
            }.value
            guard !Task.isCancelled else { return }

            imageLoader.clearAll()
            session.load(folderURL: url, fileURLs: fileURLs)
            imageLoader.startLoading(items: session.items, currentIndex: session.currentIndex)
        }
    }

    /// After Move Files: stay on the tree, reload the current folder (moved
    /// files are gone) and rebuild the tree so Picks/ and Rejects/ appear.
    private func continueAfterMove() {
        guard let current = session.folderURL else {
            closeFolder()
            return
        }
        appState = .culling
        loadFolder(current)
        rebuildTree()
    }

    private func closeFolder() {
        switchTask?.cancel()
        switchTask = nil
        session.flushSave()
        session.reset()
        imageLoader.clearAll()
        rootURL = nil
        folderTree = nil
        appState = .welcome
    }

    private func rebuildTree() {
        guard let rootURL else {
            folderTree = nil
            return
        }
        Task.detached(priority: .userInitiated) {
            let tree = FolderScanner.folderTree(rootURL: rootURL)
            await MainActor.run {
                // Ignore a stale result if the folder was closed meanwhile.
                guard self.rootURL == rootURL else { return }
                folderTree = tree
            }
        }
    }
}
```

- [ ] **Step 2: Update `CullingView` signature, layout, toolbar, and keys**

In `Sources/RawCull/Views/CullingView.swift`:

Replace the property block at the top of `CullingView`:

```swift
struct CullingView: View {
    @Environment(CullSession.self) private var session
    @Environment(ImageLoader.self) private var imageLoader
    let folderTree: FolderNode?
    let onSelectFolder: (URL) -> Void
    let onFinish: () -> Void
    let onCloseFolder: () -> Void

    @State private var isZoomed = false
    @State private var rotationQuarterTurns = 0
    @State private var showSidebar = true
    @State private var showFolderTree = true
```

Insert the tree column at the start of the `HStack(spacing: 0)`, before the `// Thumbnail sidebar` block:

```swift
        HStack(spacing: 0) {
            // Folder tree
            if showFolderTree, let folderTree {
                FolderTreePanel(
                    root: folderTree,
                    selectedURL: session.folderURL,
                    onSelect: onSelectFolder
                )
                .frame(width: 200)

                Divider()
            }

            // Thumbnail sidebar
```

Replace the `.toolbar { ... }` block:

```swift
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Close Folder") {
                    onCloseFolder()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Finish") {
                    onFinish()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(session.count == 0)
            }
        }
```

Add a folder-change reset right after the existing `.onChange(of: session.currentIndex)` modifier:

```swift
        .onChange(of: session.folderURL) { _, _ in
            resetView()
        }
```

In `handleKeyDown`, add a case to the `switch characters` block next to `case "t":`:

```swift
        case "t":
            showSidebar.toggle()
            return true
        case "f", "ㄹ":
            showFolderTree.toggle()
            return true
```

Note: `"ㄹ"` is the Korean 2-set layout character on the physical `F` key, matching how `"ㅁ"`, `"ㄴ"`, `"ㅇ"` already mirror `A`, `S`, `D`.

- [ ] **Step 3: Rename the completion button in `SummaryView`**

In `Sources/RawCull/Views/SummaryView.swift` replace:

```swift
                Button("Back to Start") {
                    onComplete()
                }
```

with:

```swift
                Button("Continue") {
                    onComplete()
                }
```

- [ ] **Step 4: Build and run all tests**

Run: `swift build 2>&1 | tail -5 && swift test 2>&1 | tail -10`
Expected: `Build complete!` and every test passes.

If the compiler complains that `Task { ... }` in `loadFolder` calls main-actor-isolated members from a nonisolated context, change it to `switchTask = Task { @MainActor in` and keep the body as is.

- [ ] **Step 5: Manual check**

Run: `swift run` and verify:

1. Open a folder that has subfolders. The tree shows on the left with the root expanded and highlighted.
2. Click a subfolder with photos: thumbnails and the photo switch; the counter resets; zoom and rotation reset.
3. Click a subfolder with no photos: "No photos in this folder" appears and `Finish` is greyed out.
4. Mark a photo, then within one second click another folder, then click back: the mark is still there.
5. Mark picks, `Finish`, `Move Files`, `Continue`: you are back on the tree, the current folder no longer lists the moved files, and `Picks/` and `Rejects/` appear under it.
6. `Close Folder` returns to the welcome screen. Press `F` while culling to hide and show the tree.

Record anything that does not match in the task report.

- [ ] **Step 6: Commit**

```bash
git add Sources/RawCull/App/ContentView.swift Sources/RawCull/Views/CullingView.swift Sources/RawCull/Views/SummaryView.swift
git commit -m "Wire folder tree into culling flow

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the status list**

Under `# Status`, replace:

```
- single-folder culling
```

with:

```
- folder tree: open a root folder and cull each subfolder in turn
```

- [ ] **Step 2: Update How It Works**

Replace the numbered list under `# How It Works` with:

```
1. Open or drop a root folder.
2. RawCull scans the top level of that folder and shows a tree of its subfolders on the left.
3. Click any folder in the tree to review the photos directly inside it. Each folder keeps its own session and its own `Picks/` and `Rejects/`.
4. Review photos one by one.
5. Decisions are saved to `.rawcull-session.json` in the folder being reviewed.
6. Press `Finish` when you are done with the current folder.
7. On the summary screen, press `Move Files` to move accepted photos into `Picks/` and rejected photos into `Rejects/`, then `Continue` to go back to the tree.
8. Press `Close Folder` to return to the start screen.
```

- [ ] **Step 3: Add the shortcut**

Under `View controls:` add after the `T` line:

```
- `F`: toggle folder tree
```

- [ ] **Step 4: Update Notes**

Replace:

```
- The app currently scans only the selected folder, not subfolders.
```

with:

```
- Each folder is culled on its own. Clicking a folder loads only the files directly inside it, not its subfolders.
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "Document the folder tree panel

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
