# Folder Tree Panel Design

Date: 2026-09-15

## Goal

Add a folder tree panel to the culling screen so a user can open one root folder
and cull each of its subfolders in turn without going back to the welcome screen.

## Scope

- The folder opened from the welcome screen becomes the **root**.
- The culling screen shows a tree of the root and every descendant folder.
- Clicking a folder loads the photos directly inside that folder (top level only,
  same rule as today). Each folder keeps its own `.rawcull-session.json` and its
  own `Picks/` and `Rejects/`.
- The saved session format does not change.

Out of scope: per-folder photo counts, recursive (flattened) culling, multi-root.

## Data

### `FolderNode` (new, `Models/FolderNode.swift`)

```swift
struct FolderNode: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let children: [FolderNode]
}
```

### `FolderScanner.folderTree(rootURL:) -> FolderNode` (new)

- Recursively lists subdirectories of `rootURL`.
- Skips hidden folders.
- Does not follow symbolic links (avoids cycles).
- Children sorted by name with `localizedStandardCompare` (natural sort).
- Files are never nodes.
- Runs on a background task alongside the photo scan.

## Session

### `CullSession.flushSave()` (new)

Cancels the pending debounced save task and calls `saveSession()` immediately.
No-op when no folder is loaded. Called before switching folders, before Close
Folder, and from `applicationWillTerminate`.

`load(folderURL:fileURLs:)` is unchanged and continues to auto-resume from an
existing session file.

## UI

### Layout

`CullingView` gains a leading column:

```
FolderTreePanel (~200pt) | ThumbnailSidebar (120pt) | PhotoView + StatusBar
```

- `FolderTreePanel` (new, `Views/FolderTreePanel.swift`) renders the tree with
  `List` + `OutlineGroup`. The row whose URL equals `session.folderURL` is shown
  selected. Clicking a row calls `onSelect(url)`.
- Keyboard `f` toggles the tree panel, mirroring `t` for the thumbnail sidebar.
- Toolbar gains a "Close Folder" button that returns to the welcome screen.
- `Finish` is disabled when the current folder has no photos.
- When the current folder has no photos, `PhotoView`'s area shows an empty state
  ("No photos in this folder") instead of a spinner.
- `StatusBar` shows `0 / 0` when `totalCount == 0` instead of `1 / 0`.

### State ownership

`ContentView` owns `rootURL: URL?` and `folderTree: FolderNode?` as `@State` and
passes them to `CullingView`. The selected folder is `session.folderURL`; no
separate selection state.

### Folder switch flow (`ContentView.switchFolder(url)`)

1. If `url == session.folderURL`, return.
2. Cancel any in-flight switch task (last click wins).
3. `session.flushSave()`.
4. Scan `url` on a background task.
5. On the main actor: `imageLoader.clearAll()`, `session.load(folderURL:fileURLs:)`,
   `imageLoader.startLoading(items:currentIndex:)`.

Existing session files are resumed silently. "Start Fresh" remains available only
when opening the root from the welcome screen.

### After Move Files

`SummaryView`'s completion button becomes "Continue". Pressing it returns to the
culling screen; `ContentView` rescans the current folder and rebuilds the tree so
the new `Picks/` and `Rejects/` folders appear. `Picks/` and `Rejects/` are
ordinary folders in the tree and can be culled again.

### Welcome and Close Folder

- Welcome flow is unchanged except it also builds the folder tree.
- Close Folder: `flushSave()`, `session.reset()`, `imageLoader.clearAll()`, clear
  `rootURL` and `folderTree`, return to welcome.

## Edge cases

- Folder deleted externally: scan returns empty, the empty state is shown, and the
  tree is rebuilt on the next rescan. No alert.
- Rapid clicks: the previous switch task is cancelled; only the last selection loads.
- App quit within the save debounce window: `applicationWillTerminate` flushes.

## Testing

- `FolderScannerTests`: `folderTree` builds nested structure, skips hidden folders,
  natural sort (`Day 2` before `Day 10`), files are not nodes.
- `CullSessionTests` (new, `@MainActor`): `flushSave()` writes decisions to the
  session file immediately; loading a second folder leaves the first folder's
  session file intact.
- Views: `swift build` must pass; manual check of switching, empty folder, and
  post-move tree refresh.

## Files

- New: `Sources/RawCull/Models/FolderNode.swift`,
  `Sources/RawCull/Views/FolderTreePanel.swift`,
  `Tests/RawCullTests/CullSessionTests.swift`
- Modified: `FolderScanner.swift`, `CullSession.swift`, `ContentView.swift`,
  `CullingView.swift`, `SummaryView.swift`, `StatusBar.swift`, `RawCullApp.swift`,
  `README.md`
