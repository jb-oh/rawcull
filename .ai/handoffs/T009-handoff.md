# T009 Handoff

Status: implemented

## Summary

Implemented thumbnail multi-selection with the binding selection model, keyboard and context-menu
batch decisions, batch Reveal in Finder, selection borders, and a wrapping selection count.
Added complete English/Korean plural strings and model, AppKit interaction, localization and layout tests.
Command-click toggles selection. Control-click follows the macOS secondary-click convention and opens
the same context menu as right-click without changing selection or the current photo.

## Files changed

- `Sources/RawCull/Models/CullSession.swift`
  - Owns selected item IDs and the anchor, click operations, collapse behavior and action targets.
  - Applies batch decisions with incremental counts and one save reservation per changed action.
  - Allows an injected session writer for write-count tests; the default still writes atomically.
- `Sources/RawCull/Views/ThumbnailSidebar.swift`
  - Adds AppKit mouse handling, native context menus, target snapshots and batch Finder reveal.
  - Adds weaker selection borders while preserving the current item's 2 pt border and filenames.
- `Sources/RawCull/Views/CullingView.swift`
  - Handles plain Escape directly and passes the selection count to the status bar.
- `Sources/RawCull/Views/StatusBar.swift`
  - Shows a localized selection count for 2+ items in the existing flow layout.
- `Sources/RawCull/Resources/Localizable.xcstrings`
  - Adds selection-count and three batch-action entries with English/Korean plural variations.
- `Tests/RawCullTests/CullSessionTests.swift`
  - Covers selection rules, nearest-item tie breaking, navigation/load/reset, Escape collapse,
    target resolution, mixed batch counts, no-op decisions and single-selection behavior.
  - Counts actual writes for flush and automatic debounce paths using temporary directories.
- `Tests/RawCullTests/ThumbnailClickTests.swift`
  - Covers Command-only toggle mapping, Shift precedence, Control-click menu routing without
    selection callbacks, target snapshots, menu actions and grouped reveal URLs for both secondary paths.
- `Tests/RawCullTests/LocalizationTests.swift`
  - Checks plural catalog structure and compiled English/Korean selection and action strings.
- `Tests/RawCullTests/StatusBarTests.swift`
  - Checks wrapping and bounds with the extra selection-count unit at narrow and wide widths.
- `.ai/handoffs/T009-handoff.md`
  - This handoff.

## Implementation notes

- Selection lives entirely in `CullSession`. External writes to `items` and `currentIndex` are
  restricted so callers cannot bypass the selection invariant. Shift replaces the range and keeps
  the anchor. Toggle removal chooses the nearest selected index; ascending order wins equal-distance
  ties. Navigation collapses even when already at the first or last item.
- Every cell has a transparent `NSViewRepresentable` overlay covering its image and caption.
  `ThumbnailClickView.mouseDown(with:)` checks Control first and opens the context menu before returning,
  without invoking `onClick`. Other left clicks use the sidebar's selection mapping: Shift extends the
  range, Command toggles and Control is excluded from the toggle modifier. Shift takes precedence
  over Command. The default mouse handler is not called.
- `menu(for:)` builds the same menu for `.rightMouseDown` and Control + `.leftMouseDown`, returning nil
  for other events. `mouseDown(with:)` for Control-click and `rightMouseDown(with:)` share
  `showContextMenu(with:)`, so they use identical target resolution, menu items and popup behavior.
  The popup callback defaults to `NSMenu.popUpContextMenu`; tests substitute a capture callback to
  verify dispatch without opening a modal menu. No SwiftUI gesture/menu ordering is involved.
- Opening a menu only reads targets. A selected cell in a multiple selection targets that selection;
  every other cell targets itself. The menu retains those target items until an action is chosen.
  Pick, Reject and Unmark share that snapshot. Reveal passes all snapshot URLs together to one
  `NSWorkspace.shared.activateFileViewerSelecting` call.
- A batch updates only items whose decision changes, then calls `scheduleSave()` once outside the
  loop. An unchanged batch schedules nothing. The injected writer exercises the same persistence
  path and preserves the existing pending-save retry behavior.
- Plain Escape is checked after the modifier/shortcut-recording guards and before the folder-loading
  guard. It returns true only when a multiple selection was collapsed, including during loading.
  Modified keys remain ignored. Rotation, zoom and Return still use the current item.
- Rejected-image dimming is applied before the selection-border overlay so both selection borders
  remain visible. Other selected cells use `FavrenColors.primary` at 55% opacity with a 1 pt border.
- Filename captions, full-name help, lazy thumbnail tasks, item IDs and scroll-to-current handlers
  are preserved. The native overlay also receives the filename as its AppKit tooltip.
- Ran `xcodegen generate` after adding the test source. The generated project had no additional diff.

## Validation

### Passed

- `swift build`: passed on the final implementation with normal SwiftPM cache/sandbox access.
- `swift test`: passed, 100 tests in 11 suites after the Command-only toggle / Control-click correction.
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`:
  passed with `BUILD SUCCEEDED` on the final implementation. Xcode reported its AppIntents metadata
  extraction warning because the app has no AppIntents.framework dependency.
- `xcodegen generate`: passed during the initial implementation; no generated-project changes beyond
  the existing staged version. Not rerun for the modifier correction because no source files were added.
- `git diff --check`: passed.
- Final diff review against the index, including the new test and handoff files: passed;
  changes are limited to T009.
- Modifier-correction diff review against a snapshot from the start of the follow-up: passed;
  only `ThumbnailSidebar.swift`, `ThumbnailClickTests.swift` and this handoff changed.
- Staged-diff SHA-256 comparison: passed. The baseline and final staged diff both hash to
  `d473186dd6126a74df0a621dedb608fb19f8e767c88ef8275d5e47983e5adc5b`.
  No staging, unstaging, commits or pushes were performed.

### Failed

- Initial restricted `swift build` and `swift test`: failed during manifest compilation with
  `sandbox-exec: sandbox_apply: Operation not permitted` and inaccessible-cache warnings.
  Both commands subsequently passed with approved normal cache/sandbox access.
- An intermediate `swift test` run: failed in the newly added automatic-save test because its fixed
  1.2 second wait could expire before the debounce task started on the busy main actor. Replaced
  that timing assumption with a bounded wait for the actual write. The final full suite passed.

### Not run

- Physical mouse/trackpad interaction, on-screen border/tooltip appearance, scroll behavior and
  Finder window selection: not exercised interactively. Automated AppKit tests cover event handler
  inputs, menu construction and actions, unchanged selection/current state and grouped reveal URLs.

## Acceptance criteria

- [x] Unit tests cover plain click, Shift in both directions, toggle add/remove, nearest remaining
      current item and lower-index ties, singleton no-op, navigation/load collapse, batch decisions,
      counts and one write, and single-selection behavior.
- [x] Shift-click extends and Command-click toggles. Right-click and Control-click open the same
      native menu without changing selection/current. Control is excluded from toggle mapping;
      both secondary menu paths and Control-click bypass of `onClick` are unit tested.
- [x] Context menu includes Pick, Reject, Unmark, separator and Reveal in Finder, with localized
      batch counts and all reveal URLs submitted together.
- [x] Selection borders and the wrapping status-bar selection count implemented as specified.
      On-screen appearance remains an interactive review item.
- [x] Catalog complete for Korean; new plural strings covered by LocalizationTests.
- [x] `swift build`, `swift test` and the Xcode app build pass.

## Deviations

None.

## Risks / concerns

- Review physical Control-click and secondary-click delivery in the running app, including a
  two-finger trackpad click. Automated tests invoke the native handlers without displaying a menu.
- Confirm borders on rejected photos, full-name tooltips, narrow status-bar wrapping and Finder's
  visible multi-file selection during interactive review.

## Suggested shared-context updates

None.
