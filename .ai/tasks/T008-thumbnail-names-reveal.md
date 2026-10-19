# T008: File names and Reveal in Finder in the thumbnail sidebar

Status: accepted
Owner: codex
Depends on: T006

## Objective

Each thumbnail in the sidebar shows its file name, and right-clicking a thumbnail offers
"Reveal in Finder".

## Why

User request (2026-10-19): see file names in the thumbnail section and jump to the file in Finder.

## Context

- `Sources/RawCull/Views/ThumbnailSidebar.swift`: `ThumbnailSidebar` (120 pt wide column, set in
  `CullingView`) and `ThumbnailCell` (75 pt tall image, decision dot, current-item border,
  rejects at 50% opacity).
- Strings are localized via `Sources/RawCull/Resources/Localizable.xcstrings` (en + ko complete).
  macOS Korean wording for Reveal in Finder: "Finder에서 보기".

## Implementation requirements

1. Under each thumbnail, the file name in a small caption font, one line, middle truncation
   (so the extension stays visible), FavrenUI secondary text color; the current item's name uses
   the primary text color. Full name as a hover tooltip.
2. Context menu on each cell: "Reveal in Finder" (selects the file in Finder via
   `NSWorkspace.shared.activateFileViewerSelecting`). Right-click must not change the current photo.
3. Keep scrolling to the current item, lazy loading and tap-to-jump working. Rejected cells keep
   their dimming, but the name stays readable.
4. Add the new string to the catalog with its ko value.

## Non-goals

- No changes to sidebar width, the folder tree, culling keys or other views.
- No rename, delete or other file operations.

## Acceptance criteria

- [ ] File names visible under thumbnails, truncated in the middle, tooltip shows the full name.
- [ ] Right-click > Reveal in Finder selects the file in Finder; current photo unchanged.
- [ ] Catalog complete for ko.
- [ ] `swift build`, `swift test`, and the `xcodebuild` app build pass.

## Required checks

- `swift build`
- `swift test`
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`

## Expected output

Changes in `ThumbnailSidebar.swift`, the catalog, and `.ai/handoffs/T008-handoff.md`.
