# T002 Handoff

Status: implemented

## Summary

Rebuilt the status bar with ideal-size units that wrap onto additional rows. Folder totals now show labeled photos, picks, rejects, and left counts. The Return/save rotation hint remains.

## Files changed

- `Sources/RawCull/Views/StatusBar.swift`
  - Added the flow layout, unbreakable position/badge and hint units, labeled statistics, and singular/plural formatting
- `Sources/RawCull/Views/CullingView.swift`
  - Passed `session.undecidedCount` at the existing status bar call site
- `Tests/RawCullTests/StatusBarTests.swift`
  - Added six tests covering count labels, ideal-size geometry across widths, stats priority, wide alignment, row spacing, and unconstrained sizing
- `.ai/handoffs/T002-handoff.md`
  - This handoff

## Implementation notes

- A single SwiftUI `Layout` measures every unit with an unspecified proposal and places it at that measured size. Size reporting and placement share the same arrangement calculation.
- Position and its decision badge form one unit. Each statistic is a separate unit so stats can also wrap at narrow widths. All four statistics precede hints, keeping them on the first row whenever they fit with position.
- Wrapped rows align left with 16 pt horizontal spacing and 8 pt line spacing. A single row adds spare width before the first hint, keeping position/stats leading and hints trailing.
- Each unit uses `fixedSize()`. The layout preserves its ideal vertical size so additional rows increase the bar's height inside the existing photo/status `VStack`.
- FavrenUI key caps, badges, colors, and the `.bar` background remain in use. No model or keyboard behavior changed.
- The layout stays in `StatusBar.swift`. No app source file was added, so Xcode project regeneration was unnecessary. SwiftPM discovers the new test file.
- Reviewed the final unstaged implementation diff and the new test/handoff files. Staged changes were left untouched; the staged diff checksum remained unchanged during verification. Nothing was committed or unstaged.

## Validation

### Passed

- `swift build`: exited 0. Log: `/tmp/rawcull-T002-swift-build.log`
- `swift test`: exited 0; 41 tests in 6 suites passed. This includes all six new status bar tests. Log: `/tmp/rawcull-T002-swift-test.log`
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`: exited 0 with `BUILD SUCCEEDED`. Log: `/tmp/rawcull-T002-xcodebuild.log`
- `git diff --check`: passed
- Final self-review: inspected only this task's unstaged changes and new files; confirmed the call-site change is limited to `undecidedCount`

### Failed

- Initial sandboxed `swift build`: failed with `sandbox-exec: sandbox_apply: Operation not permitted`. The same build subsequently passed with approved escalation. Required Swift/Xcode checks used normal cache access.
- Initial `swift test`: the new wide-layout assertion failed when comparing a `CGFloat` with an `Int` expression through `#expect`. An explicit `CGFloat` expected value corrected the assertion. The full rerun passed. Initial log: `/tmp/rawcull-T002-swift-test-initial.log`
- No failures remain in the final required checks.

### Not run

- Interactive window resizing at 360 pt and wider, rendered key-cap/label inspection, and photo-height adjustment: not run per the instruction prohibiting GUI/computer-use automation
- Interactive A/S/D count updates: not run for the same reason. The existing observable session counts are passed directly to the bar; no count state is cached there.

## Acceptance criteria

- [ ] At any width from 360 pt up no key cap or label is compressed or truncated; units wrap: implemented; geometry tests pass at every integer width from 360 through 1600 pt using representative unit sizes. Actual rendered UI verification was not run.
- [ ] Wide window renders on one line, visually close to the current bar: single-row geometry and trailing hints are tested; visual comparison was not run.
- [x] Stats show total, picks, rejects, and left with words and correct singular/plural: implemented; zero/one/many count label tests pass for photo, pick, and reject.
- [ ] Counts update live when marking A/S/D: wired to existing observable session counts; interactive verification was not run.
- [x] `swift build`, `swift test`, and the `xcodebuild` app build pass.

## Deviations

None. Interactive checks are explicitly listed as not run, as requested.

## Risks / concerns

- Geometry tests use representative ideal unit sizes. They do not measure actual SwiftUI text or FavrenUI rendering. Claude should verify narrow/wide visual behavior, photo resizing, and live count updates interactively.

## Suggested shared-context updates

None.
