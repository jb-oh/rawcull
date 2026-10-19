# T003 Handoff

Status: implemented

## Summary

Implemented centered 2x zoom geometry and an AppKit minimap. The document is at least as large as
the viewport on each axis. The photo stays centered on axes that do not scroll. Resizing preserves
the photo point at the viewport center, subject to scroll limits.

The minimap shows the rotated photo and visible region. Clicking or dragging pans the main view.
Interactive verification was not run, as instructed.

## Files changed

- `Sources/RawCull/Views/PhotoView.swift`
  - Correct document sizing, centered photo placement, and per-axis scroll elasticity.
  - Preserve normalized photo center during viewport changes; recenter on image or rotation changes.
  - Add a top-right minimap with a rotated thumbnail, border, dimming outside the white viewport
    rectangle, and click/drag navigation.
  - Add pure `ZoomGeometry` calculations for document sizing, panning, and minimap mapping.
- `Tests/RawCullTests/ZoomGeometryTests.swift`
  - Eight geometry tests, including parameterized rotation coverage.
- `.ai/handoffs/T003-handoff.md`
  - Implementation and verification record.

## Implementation notes

- Geometry and minimap mapping use the displayed, rotated photo rect, including its offset within
  the document. They do not use the unrotated image view frame.
- Both document and minimap use upward-growing y coordinates. The top of the minimap maps directly
  to the top of the photo.
- Clip bounds notifications update AppKit drawing and the stored photo center without SwiftUI state
  updates. Bounds notifications during layout are ignored. Viewport size changes retain the previous
  photo center until the new geometry is ready, including changes caused by autohiding scrollers.
- The minimap is a scroll-view subview outside the scrolling document. Its longest side is 160 pt,
  inset 12 pt from the clip viewport, shrinking only when needed to fit. It hides when the viewport
  contains the whole photo. Its hit area is limited to its own frame.
- Image replacement and normalized quarter-turn changes still request midpoint centering, even if
  the resulting display geometry is unchanged.
- The non-zoomed view, key handling, `StatusBar`, and `CullingView` were left unchanged.
- Ran `xcodegen generate` after adding the test file. It produced no unstaged project changes.
- Reviewed the final unstaged implementation diff and the new test file. The staged diff hash
  matches the initial hash. Nothing was committed, staged, or unstaged.

## Validation

### Passed

- `swift build` : final build passed outside the sandbox.
- `swift test` : final run passed all 49 tests in 7 suites, including `ZoomGeometryTests`.
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build` : final app
  build passed with `BUILD SUCCEEDED`.
- `xcodegen generate` : passed; generated project matches the existing staged project.
- `git diff --check` : passed after final code changes.

### Failed

- `swift build` (initial sandboxed attempt) : SwiftPM could not launch its manifest sandbox:
  `sandbox-exec: sandbox_apply: Operation not permitted`. The subsequent build outside the sandbox
  passed. This was an environment restriction before source compilation.

### Not run

- Interactive narrow/tall and wide viewport zoom checks : GUI automation was prohibited.
- Interactive Z/C rotation, preview/detail replacement, and saved-rotation checks while zoomed :
  GUI automation was prohibited. Rotation and resolution geometry are unit tested.
- Interactive trackpad, wheel, scroller, minimap click/drag, and outside-frame event checks :
  GUI automation was prohibited.
- Interactive window resize and T/F panel-toggle checks : GUI automation was prohibited.
- Interactive minimap appearance and hide-when-fully-visible checks : GUI automation was prohibited.

## Acceptance criteria

- [ ] Narrow/tall viewport centers the photo and scrolls only where needed : implemented and
  geometry tests passed; interactive verification not run.
- [ ] Wide viewport remains centered and scrolls both ways as needed : implemented and geometry
  tests passed; interactive verification not run.
- [ ] Z/C rotation keeps the photo centered and rotates the minimap : implemented; rotation
  geometry tests passed, but interactive verification not run.
- [ ] Top-right minimap tracks scrolling and supports click/drag panning : implemented; mapping
  tests passed, but interactive verification not run.
- [ ] Window resize and panel toggles preserve the viewed photo point : implemented and resize
  geometry tests passed; interactive verification not run.
- [x] Pure geometry helpers are unit tested, including document padding, scroll limits, rotation,
  resolution changes, resize clamping, and non-flipped minimap mapping.
- [x] `swift build`, `swift test`, and the required `xcodebuild` app build pass.

## Deviations

None. Interactive checks were omitted as explicitly instructed.

## Risks / concerns

- Visual rotation parity, live scrolling, minimap pointer handling, and AppKit layout behavior
  still need interactive review. Pure geometry tests do not verify event delivery or rendering.
- Include legacy/autohiding scrollers in resize review, since their visibility can change the
  viewport size during layout.

## Suggested shared-context updates

None.

## Correction 1

Status: implemented

### Change

- `ZoomMinimapView` now creates an aspect-preserving `NSBitmapImageRep` with a 320 px longest
  side when the source image identity changes. This supplies 2x pixels for the 160 pt minimap.
- Repeated assignments of the same `NSImage` reuse the bitmap. `draw(_:)` draws only the cached
  bitmap, so scrolling no longer resamples the full-resolution detail image on every frame.
- Rotation and viewport changes reuse the unrotated cache. Existing rotation transforms,
  viewport indicator drawing, and minimap interaction remain unchanged.
- Only `PhotoView.swift` and this appended handoff section changed for the correction.

### Validation

- Passed: `swift build`.
- Passed: `swift test`, all 49 tests in 7 suites.
- Passed: `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`,
  `BUILD SUCCEEDED`.
- Passed: `git diff --check` and review of the correction diff.
- Not run: interactive rendering and scrolling checks, as instructed. No GUI automation was used.

All three build/test commands ran outside the sandbox because of the SwiftPM sandbox restriction
recorded above and Xcode's build-cache paths. The staged diff hash remains unchanged. Nothing was
committed, staged, or unstaged.
