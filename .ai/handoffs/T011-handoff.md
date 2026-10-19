# T011 Handoff

Status: implemented

## Summary

Added a persisted, resizable thumbnail sidebar with proportional image heights.
Both panel dividers use the same AppKit resize handle.
Thumbnail decoding now targets 480 px with a 64-image cache cap.
Added an opaque toolbar background preference, content clipping, and macOS 26+
top scroll edge effect suppression. The final macOS 27 window capture remains
for Claude, as specified by the task.

## Files changed

- `Sources/RawCull/Views/CullingView.swift`
  - Adds `thumbnailSidebarWidth`, default 120 pt, clamped to 100...240 pt.
  - Generalizes the existing folder divider into `PanelResizeHandle` and one
    `PanelResizeView` class, shared by both dividers.
  - Supplies proportional thumbnail heights and configures the toolbar background.
- `Sources/RawCull/Views/ThumbnailSidebar.swift`
  - Passes image height through to each cell and scrolls to the current item when
    resizing changes that height. Existing caption and selection styling remain.
- `Sources/RawCull/Services/ImageLoader.swift`
  - Raises thumbnail decoding from 200 to 480 px and lowers the cache cap from
    300 to 64 images.
- `Tests/RawCullTests/ImageLoaderTests.swift`
  - Tests actual 480 px JPEG decoding in landscape and EXIF-rotated orientations,
    cache eviction/reloading, and RAW sidecar decoding at the new thumbnail size.
- `Tests/RawCullTests/ThumbnailClickTests.swift`
  - Runs the existing hosted click test at 100, 120, and 240 pt sidebar widths
    with proportional cell heights.
- `.ai/handoffs/T011-handoff.md`
  - This handoff.

## Implementation notes

- Width lives on `CullingView` in `@AppStorage("thumbnailSidebarWidth")`, outside
  the conditional sidebar. Toggling thumbnails does not reset the stored width.
  Both the displayed width and drag writes are clamped. Folder width limits and
  drag-coordinate calculations are unchanged. Both handles retain the horizontal
  resize cursor and a 7 pt divider hit area.
- Image height is `sidebarWidth * 75 / 120`: 62.5 pt at minimum width, 75 pt at
  default width, and 150 pt at maximum width. The existing cell padding, caption,
  highlight, clipping, rotation preview, and action handlers are retained.
- A 480 x 480 RGBA8 bitmap contains 921,600 bytes, about 0.88 MiB. At 64 entries,
  the thumbnail cache holds about 56.25 MiB of RGBA8 pixel data in the square
  worst case. For comparison, the previous 300 x 200 x 200 x 4 configuration was
  about 45.78 MiB. Non-square images use less pixel data. This is a pixel estimate,
  not a process-memory limit: NSImage/ImageIO overhead, higher-bit-depth images,
  in-flight decodes, and the separate preview/detail caches add memory. The cache
  remains count-bounded independently of a folder's photo count; its existing
  eviction mechanism is retained.
- Toolbar configuration on macOS 27 uses
  `.toolbarBackground(FavrenColors.surface, for: .windowToolbar)` for the opaque
  brand color, `.toolbarBackgroundVisibility(.visible, for: .windowToolbar)` to
  keep the background visible, and `.scrollEdgeEffectHidden(for: .top)` to suppress
  top edge effects inherited by both the folder List and thumbnail ScrollView.
  The culling HStack is clipped to its content bounds below the title bar.
  The traffic lights, title, Finish toolbar item, and `.titleBar` window style
  are unchanged. These APIs compile and build on macOS 27.0.1 with Xcode 27.0;
  their combined visual result has not been captured in this run. No claim is
  made that an individual API was visually isolated as the cause of the effect.
- On macOS 15 through 25, the same solid toolbar style and visibility modifier
  apply, without the unavailable scroll edge API. On macOS 14, visibility uses
  `.toolbarBackground(.visible, for: .windowToolbar)` instead. Content clipping
  applies on every supported version. The macOS 14 deployment target is retained;
  runtime behavior on 14/15 was not exercised.
- API references: Apple's [toolbar shape style documentation](https://developer.apple.com/documentation/swiftui/view/toolbarbackground(_:for:)-5ybst),
  [toolbar visibility documentation](https://developer.apple.com/documentation/swiftui/view/toolbarbackgroundvisibility(_:for:)),
  and [scroll edge effect documentation](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffecthidden(_:for:)).
- No source files were added or removed, so Xcode project regeneration was not
  needed. Existing staged changes remain byte-for-byte unchanged. No staging,
  unstaging, commits, or pushes were performed.

## Validation

### Passed

- `swift build`: passed with normal SwiftPM access after the sandboxed attempt
  failed at manifest startup.
- `swift test`: passed, 106 tests in 11 suites, with six known issues from the
  existing direct-window synthetic modifier limitation. Plain clicks pass at all
  three widths. Command/Shift assertions remain inside the existing narrowly
  scoped known-issue wrappers; they are not claimed as passing verification.
  Previously this same test recorded two known issues at one width; its three
  width cases now record six. See T010's handoff for the original diagnosis.
- New image loader tests: passed. A 1200 x 800 JPEG decodes to 480 x 320, and EXIF
  orientation 6 decodes to 320 x 480. The 65th cached image evicts the oldest;
  reloading that entry evicts the next oldest while preserving the other 63.
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`:
  passed with `BUILD SUCCEEDED`. Xcode emitted its AppIntents metadata-extraction
  warning because the app has no AppIntents.framework dependency.
- `git diff --check`: passed. Reviewed the T011 source/test diff against the index.
- Staged-diff comparison: passed. Binary staged patches captured before and after
  implementation compare identically with `cmp`.

### Failed

- Initial sandboxed `swift build`: failed before compiling project code with
  `sandbox-exec: sandbox_apply: Operation not permitted`. The normal-access rerun
  passed. This was a build-environment restriction, not a source compile failure.

### Not run

- Final app window capture on macOS 27: left for Claude as requested by the task.
  Opaque uniform appearance and absence of visible scrolling under the toolbar
  remain visual verification items.
- Physical divider dragging, cursor hover, shortcut hide/show persistence, and
  relaunch persistence: implemented but not exercised interactively.
- Runtime checks on macOS 14/15: those OS versions are unavailable in this run.
- `xcodegen generate`: no source file additions or removals.

## Acceptance criteria

- [x] One shared resize handle class; thumbnail sidebar width persists in
      AppStorage, clamps to 100...240 pt, and scales thumbnail height.
- [x] Thumbnails decode at 480 px with a 64-image bounded cache, documented above.
- [ ] Toolbar uniform and opaque on macOS 27, with nothing visibly scrolling
      underneath: implementation is complete; Claude's final capture is pending.
- [x] `swift build`, `swift test`, and the Xcode app build pass, subject to the
      explicitly documented existing synthetic modifier-test limitation.

## Deviations

None. The macOS 26+ scroll edge modifier is applied to the common culling ancestor;
Apple documents that it affects scroll views within that hierarchy, so separate
modifiers on `FolderTreePanel` and `ThumbnailSidebar` are unnecessary.

## Risks / concerns

- Review the toolbar across all three columns on macOS 27 while scrolling both
  lists. The API configuration and builds alone do not prove the visual criterion.
- Review minimum/maximum divider positions, pointer cursor, filename truncation,
  selected/rejected rotated thumbnails, scroll-to-current, and width persistence
  across shortcut toggles and an app relaunch.
- The thumbnail memory estimate assumes RGBA8; it is not an overall app memory cap.

## Suggested shared-context updates

None.
