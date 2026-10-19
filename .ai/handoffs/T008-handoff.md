# T008 Handoff

Status: implemented

## Summary

- Added file names below sidebar thumbnails, with middle truncation and full-name tooltips.
- Added Reveal in Finder to each cell's context menu, localized as `Finder에서 보기` in Korean.
- Kept rejected thumbnail images dimmed while rendering their names at full opacity.

## Files changed

- `Sources/RawCull/Views/ThumbnailSidebar.swift`
  - Caption, tooltip and per-item Finder context menu.
- `Sources/RawCull/Resources/Localizable.xcstrings`
  - Complete English and Korean Reveal in Finder entry.
- `Tests/RawCullTests/LocalizationTests.swift`
  - Added the new menu key to existing compiled English/Korean translation assertions.
- `.ai/handoffs/T008-handoff.md`
  - Implementation and validation results.

## Implementation notes

- Uses the existing `PhotoItem.filename`. Caption and tooltip use verbatim text so file names
  are displayed literally. The caption uses `.caption2`, one line and middle truncation.
- Current-item names use `FavrenColors.onSurface`; other names use `onSurfaceVariant`.
  The existing image, decision dot, border and reject opacity remain in a thumbnail subview.
  The caption sits outside its opacity modifier so rejected names remain readable.
- The context-menu action calls `NSWorkspace.shared.activateFileViewerSelecting([item.url])`
  for the clicked cell. It does not call session navigation or change the current index.
  The existing tap gesture remains the only cell action that jumps to a photo.
- A rectangular content shape covers both image and caption. LazyVStack, item IDs, thumbnail
  loading tasks and scroll-to-current logic are unchanged. Sidebar width remains 120 pt.
- No source files were added or removed, so Xcode project regeneration was not required.

## Validation

### Passed

- `swift build`: passed with normal build-cache access after the restricted attempt below.
- `swift test`: passed, 68 tests in 10 suites. Includes catalog completeness and compiled
  English/Korean values for Reveal in Finder.
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`:
  passed with `BUILD SUCCEEDED`.
- `git diff --check`: passed.
- Final source/test diff review against the index: passed, limited to T008 changes.
- Staged-diff SHA-256 comparison: passed. Before and after:
  `c9544b268263c6342180b77167e1b90f80fd554e44c830c5aa3624ff73349df1`.
  No staging, unstaging, commits or pushes were performed.

### Failed

- Initial restricted `swift build`: failed during manifest evaluation with
  `sandbox-exec: sandbox_apply: Operation not permitted`, alongside inaccessible SwiftPM cache
  warnings. The same build passed with approved normal cache/sandbox access.

### Not run

- Interactive caption truncation, full-name tooltips, current-item colors and rejected-name
  readability: GUI and computer-use automation were explicitly prohibited.
- Right-clicking a non-current cell, selecting Reveal in Finder, checking Finder selection and
  confirming the current photo is unchanged: same reason.
- Interactive tap-to-jump, lazy loading and scrolling to the current item: same reason.

## Acceptance criteria

- [ ] File names visible under thumbnails, middle truncation and full-name tooltips:
      implemented and source-reviewed; interactive appearance and hover checks not run.
- [ ] Right-click > Reveal in Finder selects the file without changing the current photo:
      implemented and source-reviewed; runtime Finder and gesture checks not run.
- [x] Catalog complete for Korean: completeness and compiled translation tests passed.
- [x] `swift build`, `swift test` and the Xcode app build pass.

## Deviations

None. Interactive checks are explicitly not run as requested.

## Risks / concerns

- Claude should verify caption appearance and tooltips, then right-click a non-current item
  and confirm Finder selects that file while the current photo stays unchanged.
- Scroll-to-current and tap-to-jump still need interactive confirmation with taller cells.

## Suggested shared-context updates

None.
