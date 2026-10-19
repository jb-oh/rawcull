# T010 Handoff

Status: implemented

## Summary

Removed the thumbnail AppKit click overlay. Cells now use SwiftUI taps and native context menus.
Added visible whole-cell selection styling, batch rotation previews and saves, immediate menu
rotation, partial-failure feedback, and complete English/Korean strings.
The binding T009 selection model is unchanged.

## Files changed

- `Sources/RawCull/Views/ThumbnailSidebar.swift`
  - Uses `.onTapGesture` with `NSEvent.modifierFlags` and `.contextMenu` with target snapshots.
  - Highlights the image and filename together; previews rotation on selected batch thumbnails.
  - Retains decision counts and Finder reveal; adds Rotate Left and Rotate Right.
- `Sources/RawCull/Views/CullingView.swift`
  - Saves `session.actionTargets`, routes menu rotations through the same writer, and shows batch
    feedback independently of the current photo.
  - Tracks pending rotation and per-file save progress; resets pending rotation on selection changes.
- `Sources/RawCull/Services/RotationWriter.swift`
  - Adds a sequential asynchronous batch helper with cache barriers, saved/failed URLs and messages.
  - Existing atomic metadata and RAW sidecar write implementations are unchanged.
- `Sources/RawCull/Resources/Localizable.xcstrings`
  - Adds rotation menu titles and plural-aware success/partial-failure messages in English and Korean.
- `Tests/RawCullTests/ThumbnailClickTests.swift`
  - Replaces deleted-overlay tests with a hosted-window event test and modifier-mapping checks.
- `Tests/RawCullTests/RotationWriterTests.swift`
  - Tests actual temporary JPEG batches, cache rotation, a middle failure, busy-file skipping,
    barrier ownership, and pending-preview reconciliation/reset behavior.
- `Tests/RawCullTests/LocalizationTests.swift`
  - Verifies menu translations and compiled batch feedback, including both plural substitutions.
- `.ai/handoffs/T010-handoff.md`
  - This handoff.

## Implementation notes

- Plain, Command and Shift taps use the existing `CullSession.select` rules. Control is explicitly
  ignored by the selection adapter, including combinations with Command/Shift. Secondary menus
  are handled by SwiftUI. The menu builder reads `contextMenuTargets(index:)` and its buttons
  retain the resulting items. Opening the menu has no selection or navigation mutation.
- Each cell has 4 pt inner padding and a 6 pt rounded outline around its image and filename.
  Other selected cells use `FavrenColors.primary` at 15% background opacity and a 2 pt border at
  70% opacity. The current cell uses 25% background opacity and a full-opacity 2 pt primary border.
  Rejected thumbnails retain 50% image opacity; the whole-cell background and border are outside
  that dimming. Placeholder fill uses `FavrenColors.surfaceVariant`.
- Z/C retain one pending quarter-turn value. The main photo previews it; with multiple selection,
  every selected thumbnail previews it too. A completed file has its saved turns removed from
  its temporary preview immediately, so cache updates do not visibly double-rotate it while the
  remaining files are being written.
- Return snapshots the action-target URLs. Repeated Return for the same pending save is ignored
  while it runs, as with the previous single-file in-flight guard. Z/C can continue changing the
  pending turns. Completion subtracts the saved turns once if any file succeeded; an entirely
  failed save retains pending turns. Selection/reset invalidates the preview's write token, so
  callbacks from an older save cannot subtract from a new selection's pending rotation.
- Selection-ID changes reset pending rotation even if currentIndex stays unchanged, including
  Escape and removing a non-current selection. Current-index/folder changes retain the existing
  resetView behavior. Navigation explicitly resets pending turns at folder boundaries too.
  Selection-only resets do not change zoom.
- Menu Rotate Left/Right immediately write -1/+1 turns to the menu snapshot. They do not consume
  unrelated pending keyboard rotation.
- The batch helper calls `beginRotationWrite` on the main actor, awaits one detached file write,
  then calls `applySavedRotation` or `cancelRotationWrite` on the main actor. Errors do not stop
  later files. Busy URLs count as failed/not saved, and their existing barriers are left intact.
- Batch feedback has no current-photo filter. Single-photo success, RAW-sidecar success, error,
  and silent busy-file behavior retain their previous wording/behavior.
- Partial-failure text uses explicit `saved` and `failed` plural substitutions. This avoids
  ambiguous repeated-integer plural inference and supports both English counts independently.
- No source files were added or removed. The Xcode project does not need regeneration.
  No staging, unstaging, commits or pushes were performed.

## Validation

### Passed

- `swift build`: rerun after the review correction and passed with normal SwiftPM access.
- `swift test`: rerun after the review correction and passed, 104 tests in 11 suites, with two
  known issues limited to direct-window dispatch without a current application event.
  The hosted Command/Shift selection assertions are not claimed as passing proof.
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`:
  rerun after the review correction and passed with `BUILD SUCCEEDED`. Xcode emitted its
  AppIntents metadata-extraction warning because no AppIntents.framework dependency is present.
- Modifier-source helper test: passed. The gesture now calls `selectionModifiers`, which prefers
  `NSApp.currentEvent?.modifierFlags` and falls back to `NSEvent.modifierFlags` only when the
  event is absent. Tests cover no modifiers, Command, Shift, Command+Shift and Control, including
  an event with empty flags overriding nonempty fallback flags. The fallback is evaluated only
  when the supplied current event is nil.
- Hosted plain-click path: passed. The real sidebar and its environments are hosted in an
  offscreen 120x600 NSWindow. Synthetic leftMouseDown/leftMouseUp events sent through
  `window.sendEvent` at the measured third-cell center change selection from index 0 to 2.
- Temporary JPEG batch tests: passed. All-success batches rotate orientation and cached thumbnails.
  A corrupt second file and a busy third file do not prevent saving the fourth file; failed/busy
  bytes remain unchanged, and the busy file's barrier remains owned by the original write.
- English/Korean catalog completeness and compiled plural resolution: passed, including zero,
  singular and multiple saved counts and independently varying failed counts.
- `git diff --check`: passed. Review-correction diff reviewed against a working-tree snapshot;
  only the sidebar, thumbnail click tests and this handoff's Validation section changed.
  Staged diff remains byte-for-byte unchanged.

### Failed

- Unwrapped hosted Command/Shift assertions after switching to `NSApp.currentEvent`: failed.
  Command produced `{2}` instead of `{0, 2}`; Shift produced `{2}` instead of `{0, 1, 2}`.
  All three event pairs reached the gesture and set currentIndex to 2.
- A diagnostic rerun temporarily logged `NSApp.currentEvent` inside `.onTapGesture`. For plain,
  Command and Shift clicks alike, it was `nil`: event type `nil`, event modifierFlags `nil`.
  The fallback global modifierFlags raw value was `0` for all three. The synthetic mouse events
  themselves carried Command `1048576` or Shift `131072`. The diagnostic output is in
  `/tmp/rawcull-t010-review-current-event.log`; temporary production logging was removed.
- Because direct `window.sendEvent` leaves no current application event in this test process,
  the corrected helper still uses the global fallback. As permitted by the review request,
  `withKnownIssue` is retained only when the current event is nil, global Command/Shift flags
  are absent and the actual selection matches the observed plain-click result. The genuine
  Command/Shift selection expectations remain inside those wrappers. They are not replaced
  with direct selection calls.
- Earlier T010 development runs failed on nested SwiftPM sandbox startup and intermediate test
  harness errors. Those were corrected before the original handoff; final checks above were
  rerun for this review fix.

### Not run

- `xcodegen generate`: not run because no source files were added or removed.
- Physical mouse/trackpad Command-click, Shift-click, Control-click/right-click menu behavior,
  live batch preview appearance and menu actions in the running app: not run interactively.
- Finder window selection: not run interactively.

## Acceptance criteria

- [x] AppKit overlay removed; SwiftUI tap/context menu installed; Control is excluded from selection.
- [x] Hosted-window plain-click test passes. Synthetic modifier limitations are documented above;
      Command/Shift selection assertions remain visible as two known issues, not passing proof.
- [x] Whole-cell selection styling implemented and described, with full-strength current styling
      and rejected-image dimming kept separate.
- [x] Batch preview, Return save, immediate menu rotations, partial failures and selection resets
      implemented. Single-photo feedback strings are retained.
- [x] Temporary-JPEG batch tests cover successes, a middle failure and busy-file skipping.
- [x] Complete Korean catalog and new plural tests; required build/test/app-build checks pass,
      subject to the explicit hosted modifier-test limitation.

## Deviations

The synthetic-event fallback concerns modifier state rather than lost tap delivery: this test
process delivers the taps, but does not update `NSEvent.modifierFlags` from event-local flags.
Full hosted Command/Shift selection remains unverified. No product-scope deviations.

## Risks / concerns

- Review physical Command/Shift and secondary clicks in the running app. The hosted test proves
  the SwiftUI hit-test/tap route for plain clicks; model tests prove modifier-to-selection rules.
- Review whole-cell highlights on rejected images and batch preview/save feedback visually.
- After partial success, the shared pending turns are reduced once and the badge reports failures.
  Failed photos can be reselected and retried explicitly.

## Suggested shared-context updates

None.
