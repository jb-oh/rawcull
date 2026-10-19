# T006 Handoff

Status: implemented

## Summary

- Folder tree defaults to 260 pt, with a draggable divider clamped to 200...420 pt.
- Width persists through `@AppStorage("folderTreeWidth")` and is retained when toggling the tree.
- Removed the Close Folder toolbar button. Added File > Close Folder with Command W while a
  folder is open, calling the existing `ContentView.closeFolder()` flow.
- The disabled folder command releases Command W to the standard window Close command.

## Files changed

- `Sources/RawCull/Views/CullingView.swift`
  - Persisted, bounded tree width; AppKit-backed divider drag target and horizontal resize cursor;
    removed the toolbar button and its callback parameter.
- `Sources/RawCull/App/ContentView.swift`
  - Publishes the existing close action through a focused scene value only when `rootURL` is set.
- `Sources/RawCull/App/RawCullApp.swift`
  - Focused-value key and File menu command, placed before the standard New/Close commands.
- `Tests/RawCullTests/LocalizationTests.swift`
  - Checks the compiled English and Korean translations of Close Folder.
- `.ai/handoffs/T006-handoff.md`
  - Implementation, validation results and remaining interactive checks.

## Implementation notes

- The divider has a 7 pt hit area around the existing system Divider. Native cursor rectangles
  provide the resize cursor without balancing cursor pushes/pops when the tree disappears.
- Each drag captures the initial width and mouse position in window coordinates. Resizing moves
  the divider, so using local coordinates or repeatedly adding the full translation would drift.
  Both stored-width reads and drag writes are clamped. Visibility toggles do not write the width.
- `focusedSceneValue` keeps the command tied to the active content scene, including the summary
  screen while its folder remains open. The Settings scene does not publish a close action.
- Close Folder reuses its existing catalog entry, including Korean `폴더 닫기`. No new strings,
  source files or project regeneration were needed. Thumbnail width remains 120 pt; Finish,
  status bar, photo view and Settings implementation were not changed.

### Command W routing rationale

This is static reasoning from the compiled command declaration and standard File menu layout.
No running `NSApp.mainMenu` inspection or GUI automation was performed.

- `CommandGroup(before: .newItem)` places Close Folder ahead of the standard File commands,
  including the existing window Close item. The default commands are not replaced.
- Folder open: the focused action is non-nil, so Close Folder is enabled with Command W. It is
  the first matching File menu item, so AppKit should dispatch to the existing folder-close
  flow. That flow resets the session and shows Welcome without closing the window.
- No folder open: the focused action is nil, so Close Folder is disabled and its shortcut is
  explicitly nil. It cannot compete with the standard Close item's Command W, which retains
  normal window closing. This avoids depending on duplicate-shortcut handling for disabled items.
- The disabled Close Folder item remains visible, but does not display a shortcut until enabled.
  Runtime confirmation of both states remains an interactive check.

## Validation

### Passed

- `swift build`: final run passed after making the optional focused action's type explicit.
- `swift test`: final run passed, 68 tests in 10 suites, including the new Close Folder
  translation assertion and full English/Korean catalog completeness checks.
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`:
  passed with `BUILD SUCCEEDED`.
- `git diff --check`: passed.
- Final source/test diff review: completed against the index, preserving earlier staged tasks.
- Staged-diff SHA-256 comparison: passed. Before and after:
  `4bb54aedd83d843ec5557f4c2266aa17009698ec5facd03898c5c3db2835bce6`.
  No files were staged, unstaged, committed or pushed.

### Failed

- Initial restricted `swift build`: failed because `sandbox-exec` could not apply its nested
  sandbox. Reran successfully with approved normal build-cache access.
- First build after that retry: failed with Swift's "failed to produce diagnostic for expression"
  in `ContentView.body`. The inline nil/method-reference conditional caused a type-inference
  failure. Replaced it with an explicitly typed optional action property; the next build passed.
  This was an implementation issue in this task, not a pre-existing failure.

### Not run

- Interactive divider dragging, hover cursor, minimum/maximum limits and tree shortcut toggling:
  GUI/computer-use automation was explicitly prohibited.
- Interactive relaunch to verify persisted width: same reason.
- Running File menu / `NSApp.mainMenu` inspection and Command W in open-folder, Welcome and
  Settings states: same reason. Static routing rationale is documented above.
- Interactive English/Korean menu and toolbar appearance: same reason. Compiled translations
  were verified by tests.

## Acceptance criteria

- [ ] Default 260 pt width, drag limits 200...420, persistence and toggle retention: implemented;
      interactive dragging and relaunch confirmation were not run.
- [x] No Close Folder toolbar button: verified by source diff review.
- [ ] File > Close Folder / Command W closes the folder, and disabled Command W closes the
      window normally: implemented with static routing reasoning; runtime interaction was not run.
- [x] Korean localization catalog stays complete: no new keys; completeness and compiled
      Close Folder translation tests passed.
- [x] `swift build`, `swift test` and the Xcode app build passed.

## Deviations

None. Interactive checks remain explicitly not run as requested.

## Risks / concerns

- Claude should verify actual Command W routing in both folder states and confirm drag/cursor
  behavior plus persisted width before final acceptance. Static reasoning is not a runtime test.
- Unrelated unstaged changes to `.ai/decisions.md` and `.ai/plan.md`, plus untracked T007/T008
  task files, appeared during this session. They were left untouched and are not part of T006.

## Suggested shared-context updates

None.
