# T007 Handoff

Status: implemented

## Summary

- Photos in exactly named `Picks` and `Rejects` folders default to their folder's decision.
  Saved decisions, including explicit undecided entries, take precedence.
- Single-folder and tree moves keep matching decisions in place, send opposite decisions to
  the sibling folder, and return undecided photos to the parent. RAW sidecars follow.
- Summary messages describe returns in English and Korean. Ordinary-folder messages remain
  unchanged. Continue rebuilds the tree from the parent when a sorted folder was opened directly.

## Files changed

- `Sources/RawCull/Services/FileMover.swift`
  - Shared `SortedFolder` helper, destination routing, three-outcome move results and progress,
    folder defaults in session totals, and actual move counts for button availability.
- `Sources/RawCull/Models/CullSession.swift`
  - Folder-based defaults when saved filename decisions are missing.
- `Sources/RawCull/Views/SummaryView.swift`
  - Correct button availability for undecided-only sorted folders, return warnings and results.
- `Sources/RawCull/App/ContentView.swift`
  - Expand a directly opened sorted root to its parent after moving, using the existing
    Continue/reload/rebuild flow so sibling and parent destinations are visible.
- `Sources/RawCull/Resources/Localizable.xcstrings`
  - Three new entries with complete English and Korean translations and English plural forms.
- `Tests/RawCullTests/CullSessionTests.swift`
  - Defaults, exact-name matching, saved overrides, counts, session deletion and reload coverage.
- `Tests/RawCullTests/FileMoverTests.swift`
  - Both sorted folders, RAW sidecars, progress, parent/sibling collisions, totals, tree moves,
    undecided-only sessions and incoming-photo snapshot coverage.
- `Tests/RawCullTests/LocalizationTests.swift`
  - Compiled English/Korean summary text and plural checks, plus ordinary-message regressions.
- `.ai/handoffs/T007-handoff.md`
  - Implementation and validation handoff.

## Implementation notes

- `SortedFolder` lives in the existing FileMover source file. It is the single place that
  recognizes exact case-sensitive names and derives the decision, parent and sibling.
  No source files were added or removed, so Xcode project regeneration was unnecessary.
- `MoveResult` and `TreeMoveResult` count picks/rejects by destination and expose a separate
  `returnedToParent` count. In-place photos do not advance progress or count as moved.
  `SessionTotals.filesToMove` and the same routing helper enable return-only operations.
- Tree moves snapshot all eligible sessions before changing files. Photos arriving during
  the batch are not processed again or assigned stale decisions from a destination session.
  Folders without sessions or without actual moves are skipped; their session files remain.
  Successfully processed folders have their session files removed as before.
- Existing move-error behavior is preserved: no overwrite, first failure stops the operation,
  completed moves remain, and a sidecar failure can leave its photo already at the destination.
- Changes are unstaged. No staging, unstaging, commits or pushes were performed.

## Validation

### Passed

- `swift build`: passed with normal SwiftPM cache/compiler sandbox access after the restricted
  attempt listed below.
- `swift test`: passed, 82 tests in 10 suites. Includes all new filesystem, loading and compiled
  localization checks, plus the existing ordinary-folder tests.
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`:
  passed with `BUILD SUCCEEDED`. The build emitted an App Intents metadata-extraction warning
  because there is no AppIntents.framework dependency. Log: `/tmp/rawcull-t007-xcodebuild.log`.
- `git diff --check`: passed.
- Final unstaged source, test and catalog diff review against the index: passed, limited to T007.
- Staged-diff SHA-256 comparison: passed. Before and after:
  `b88457e733f7218b0198a1db9c089d18a8cf0d588b6c7199434c0df8fee6e084`.

### Failed

- Initial restricted `swift build`: failed during manifest evaluation with
  `sandbox-exec: sandbox_apply: Operation not permitted`, with inaccessible SwiftPM cache
  warnings. The same command passed when rerun with normal cache/compiler sandbox access.

### Not run

- Interactive opening of `Picks`/`Rejects` and inspection of decision badges and summary counts:
  GUI and computer-use automation were explicitly prohibited. Model behavior is unit tested.
- Interactive single-folder and Move All Folders actions, button states, progress and displayed
  English/Korean summary layout: same reason. Routing and message values are unit tested.
- Interactive Continue/reload and tree visibility after directly opening a sorted root:
  same reason. The existing flow and the small parent-root adjustment were source reviewed;
  filesystem tree rebuilding is covered by unit tests.

## Acceptance criteria

- [x] Loading `X/Picks` without a session defaults every photo to pick; `X/Rejects` to reject:
      verified by model tests. Interactive badges not run.
- [x] Sorted single-folder moves send opposite decisions to siblings and undecided photos to
      parents; matching photos stay, sidecars follow, and no nested sorting folders are created.
- [x] The same behavior works through tree moves, including a sorted root and return-only sessions.
- [x] Sorted summary messages describe sibling moves and parent returns; compiled English and
      Korean messages and catalog completeness pass. Interactive layout not run.
- [x] Temp-directory unit tests cover defaults, sorted moves, tree moves, collisions and totals.
- [x] `swift build`, `swift test` and the Xcode app build pass.

## Deviations

None. The ContentView adjustment is required to show destinations outside a directly opened
sorted root. Interactive checks were not run as requested.

## Risks / concerns

- Claude should verify the summary's return-only button states and displayed messages, then
  Continue after opening a sorted folder directly and confirm the parent and sibling are visible.
- Sidecar collisions intentionally preserve the existing partial-move behavior described above.

## Suggested shared-context updates

None.
