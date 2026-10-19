# T011: Resizable thumbnail sidebar and a uniform toolbar background

Status: accepted
Owner: codex
Depends on: T010

## Objective

1. The thumbnail sidebar width is user-resizable by dragging its divider, like the folder tree.
2. The window's top toolbar area looks like one uniform bar. Today the thumbnail column and the
   photo area show through under it.

## Why

User feedback (2026-10-19, screenshot): asked for a resizable thumbnail bar. They also dislike
that the top bar shows different colors over each column: the thumbnail list scrolls up under the
toolbar and is visible through it, while the photo area and folder tree show their own colors.
The machine runs macOS 27. Since macOS 26 the window toolbar is translucent and SwiftUI scroll
views extend under it with a scroll edge effect. The app's deployment target is macOS 14.

## Context

- `CullingView`: the folder tree uses `@AppStorage("folderTreeWidth")` (default 260, clamped
  200...420) and a private `FolderTreeResizeHandle` (`NSViewRepresentable` + `NSView` with
  resize cursor, `mouseDown`/`mouseDragged`) overlaid on a `Divider`. The thumbnail sidebar is
  `ThumbnailSidebar(...).frame(width: 120)` followed by a `Divider`.
- `ThumbnailCell` (`ThumbnailSidebar.swift`) has a fixed 75 pt image height, 4 pt inner padding,
  file name caption, selection background and border (T010).
- `ImageLoader.loadThumbnailIfNeeded` decodes thumbnails at 200 px max (`decode(url, 200)`) and
  keeps an LRU cache (`thumbnailCache`, `thumbnailAccessOrder`). Folders can hold 6,000+ photos.
- The toolbar holds only the "Finish" button (`.primaryAction`); the window uses
  `.windowStyle(.titleBar)` in `RawCullApp`. The folder tree shows the traffic lights and title
  above it.

## Implementation requirements

### A. Thumbnail sidebar resize

1. Generalize the folder tree resize handle into one reusable private handle (for example
   `PanelResizeHandle`) used by both dividers. Do not duplicate the class.
2. Thumbnail sidebar width: `@AppStorage("thumbnailSidebarWidth")`, default 120, clamped
   100...240, resize cursor on hover, persisted across launches, kept when toggling the sidebar
   with its shortcut.
3. The thumbnail image height scales with the width, keeping today's ratio (75 pt image at the
   120 pt column). Filename caption, selection highlight, rotation preview and scroll-to-current
   keep working at every width.
4. Decode thumbnails large enough for the widest column on a 2x display (about 480 px instead of
   200 px). Check the thumbnail cache's limit and keep its memory bounded for large folders
   (state the per-image size and the cap in the handoff; adjust the cap if needed).

### B. Uniform toolbar background

5. Make the top toolbar area an opaque, uniform bar across the whole window. Content (folder
   tree, thumbnail list, photo) must start below it and must not show through it. Use public
   SwiftUI APIs with availability checks, for example
   `toolbarBackgroundVisibility(.visible, for: .windowToolbar)` (macOS 15+) and
   `toolbarBackground(.visible, for: .windowToolbar)` (macOS 13+), plus whatever macOS 26+
   needs so scroll views do not run under the toolbar (for example disabling the top scroll
   edge effect on the thumbnail and folder tree scroll views). Keep the traffic lights, title and
   Finish button where they are.
6. Document in the handoff which API produced the effect on macOS 27 and what happens on 14/15.

## Non-goals

- No changes to the folder tree behaviour, status bar, zoom, Settings, selection or rotation logic.
- No `NavigationSplitView` migration.

## Acceptance criteria

- [ ] One shared resize handle class; thumbnail sidebar resizes within 100...240, persists, and
      its thumbnails scale.
- [ ] Thumbnails decoded at about 480 px with a bounded cache, documented.
- [ ] Toolbar area uniform and opaque on macOS 27; nothing scrolls visibly under it.
- [ ] `swift build`, `swift test`, and the `xcodebuild` app build pass.

## Required checks

- `swift build`
- `swift test`
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`

## Expected output

Changes in `CullingView`, `ThumbnailSidebar`, `ImageLoader`, possibly `FolderTreePanel` and
`RawCullApp`, and `.ai/handoffs/T011-handoff.md`. Claude verifies the toolbar visually with a
window capture after the run.
