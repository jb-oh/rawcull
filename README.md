# RawCull

RawCull is a macOS SwiftUI app for quickly reviewing a folder of photos and sorting them into `Picks/` and `Rejects/`.

It is designed for fast keyboard-first culling:

- load one folder
- step through images
- accept, reject, or unmark
- optionally zoom and rotate while reviewing
- move decided files at the end

# Status

This project is an early local prototype.

Current scope:

- folder tree: open a root folder and cull each subfolder in turn
- resumable decisions via `.rawcull-session.json`
- thumbnail sidebar
- keyboard navigation
- final move into `Picks/` and `Rejects/`

# Requirements

- macOS 14 or newer
- Swift 6 toolchain
- Xcode 16 or equivalent Apple SDKs

# Build

From the repository root:

```bash
swift build
```

Run with:

```bash
swift run
```

# How It Works

1. Open or drop a root folder.
2. RawCull scans the top level of that folder and shows a tree of its subfolders on the left.
3. Click any folder in the tree to review the photos directly inside it. Each folder keeps its own session and its own `Picks/` and `Rejects/`.
4. Review photos one by one.
5. Decisions are saved to `.rawcull-session.json` in the folder being reviewed.
6. Press `Finish` when you are done with the current folder.
7. On the summary screen, press `Move Files` to move accepted photos into `Picks/` and rejected photos into `Rejects/`, then `Continue` to go back to the tree.
8. Press `Close Folder` to return to the start screen.

Important:

- pressing accept or reject does not move files immediately
- files move only from the summary screen
- undecided files stay in place

# Supported File Types

RawCull accepts any image format that macOS can decode through ImageIO. This includes camera RAW formats (for example ARW, CR3, NEF, DNG, RAF, PEF) and common formats (JPEG, HEIC, PNG, TIFF, WebP, GIF).

Animated or multi-page files show their first frame.

# Keyboard Shortcuts

Navigation:

- `Left` / `Up`: previous photo
- `Right` / `Down`: next photo

Decisions:

- `A`: accept
- `S`: unmark
- `D`: reject

View controls:

- `Space`: zoom in or out
- `Z`: rotate counterclockwise
- `X`: reset zoom and rotation
- `C`: rotate clockwise
- `T`: toggle thumbnail sidebar
- `F`: toggle folder tree

The app also handles the same physical keys across keyboard layouts, including Korean input layouts.

# Project Layout

- [`Package.swift`](/Users/jboh/repo/rawcull/Package.swift): Swift Package entry point
- [`Sources/RawCull/App`](/Users/jboh/repo/rawcull/Sources/RawCull/App): app bootstrap and top-level state flow
- [`Sources/RawCull/Models`](/Users/jboh/repo/rawcull/Sources/RawCull/Models): culling session and photo model
- [`Sources/RawCull/Services`](/Users/jboh/repo/rawcull/Sources/RawCull/Services): folder scan, image loading, and file moves
- [`Sources/RawCull/Views`](/Users/jboh/repo/rawcull/Sources/RawCull/Views): SwiftUI screens and AppKit-backed image interaction

# Notes

- Each folder is culled on its own. Clicking a folder loads only the files directly inside it, not its subfolders.
- The move step is destructive in the sense that files are relocated, not copied.
- The `.build/` directory is local-only and is ignored by Git.
