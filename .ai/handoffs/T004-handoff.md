# T004 Handoff

Status: implemented

## Summary

Added a standard SwiftUI Settings scene with a Shortcuts tab for all 12 culling actions.
Users can add plain physical keys, remove individual keys, restore defaults, and see inline
conflict feedback. Settings and culling share one observable store. Status hints follow the
first remaining binding and disappear when their action is unbound.

## Files changed

- `Sources/RawCull/Models/KeyBinding.swift`
  - All culling actions, localized action names, Codable key bindings, and the fixed ANSI label table
- `Sources/RawCull/Models/KeyBindingStore.swift`
  - Observable bindings, JSON persistence, validation/fallback, conflict moves, defaults, and recording state
- `Sources/RawCull/Views/SettingsView.swift`
  - Extensible tabbed Settings window, key recording, removable key caps, empty states, and conflict notices
- `Sources/RawCull/Views/KeyboardEventMonitor.swift`
  - Extracted the existing monitor for reuse and limited dispatch to its own key window
- `Sources/RawCull/App/RawCullApp.swift`
  - One shared store injected into both the main window and Settings scene
- `Sources/RawCull/Views/CullingView.swift`
  - Store-based keyCode dispatch, recording suppression, and plain-key modifier filtering
- `Sources/RawCull/Views/StatusBar.swift`
  - Current first bindings instead of fixed key labels, with unbound hints omitted
- `Tests/RawCullTests/KeyBindingStoreTests.swift`
  - 13 tests covering defaults, lookup, persistence, corruption, canonical labels, conflicts,
    removal, unsupported keys, restore, recording state, and ANSI label coverage
- `RawCull.xcodeproj/project.pbxproj`
  - Regenerated with XcodeGen to include the four new source files
- `.ai/handoffs/T004-handoff.md`
  - This handoff

## Implementation notes

- Bindings are encoded as Codable JSON data under the single `cullingKeyBindings` UserDefaults key.
  Each test uses a unique UserDefaults suite and removes its persistent domain afterward.
- Missing, undecodable, incomplete, duplicate, or unsupported stored bindings fall back to the
  full default set. Empty action arrays remain valid. Loaded labels are rebuilt from the fixed
  ANSI table, so a persisted Korean character cannot change a physical key's display label.
- Adding a key appends it, preserving the current first binding. Removing that first key
  promotes the next one. To replace Pick's default A with Q, remove A and add Q.
- A conflict removes the key from its former action and returns that action for inline feedback.
  An action can lose its final key and displays None.
- The shared recording state prevents culling dispatch while a key is being recorded.
  The reused event monitor also checks its host window, so Settings input cannot reach the
  culling handler. Recording cancels on Escape, tab disappearance, or window focus loss.
- Command, Control, Option, and Shift events pass through without culling or capture.
  Normal plain keys are still swallowed during folder loading. Unbound plain keys otherwise
  fall through. No character-based aliases remain.
- The grouped view hint retains only the first key of each bound view action. It disappears
  if all three view actions are unbound.
- `ContentView` needed no change because it inherits the main window's environment.
  No language setting or menu shortcut editing was added. Cmd+Return Finish remains fixed.
- Reviewed the complete unstaged tracked diff and all new source/test files. The staged diff's
  SHA-256 remained `702e86d926944789e7919c549cee87a23fab9ec9adc7c08617dcfc0da12806b3`.
  Nothing was staged, unstaged, committed, or pushed.

## Validation

### Passed

- `xcodegen generate`: regenerated the project successfully
- `swift build`: final run exited 0 with no compiler warnings
- `swift test`: final run exited 0; 62 tests in 8 suites passed, including all 13 new tests
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`:
  final run exited 0 with BUILD SUCCEEDED; log at `/tmp/rawcull-t004-xcodebuild.log`
- `git diff --check`: passed after removing a trailing blank line
- Staged-diff integrity check: SHA-256 matched before and after implementation

### Failed

- No remaining failures on the final source.
- Initial restricted-sandbox SwiftPM attempts failed before compilation with
  `sandbox_apply: Operation not permitted`. A restricted Xcode retry also failed to write a
  package-manifest diagnostics cache. Rerunning the same required checks with sandbox
  escalation passed. These were environment restrictions, not attributed to existing code.
- An intermediate build exposed new actor-isolation warnings in the extracted monitor.
  The first correction failed compilation because it returned a non-Sendable NSEvent from
  `MainActor.assumeIsolated`. The final callback returns only a Bool from that closure and
  keeps the event local. Both final builds passed.

### Not run

- Interactive Cmd+, and app-menu Settings opening: GUI automation prohibited by the task invocation
- Interactive add/remove recording, Escape cancellation, modifier pass-through, conflict feedback,
  Restore Defaults, and focus/window isolation: GUI automation prohibited
- Live culling rebind and immediate status-hint update: GUI automation prohibited
- App restart persistence check: GUI automation prohibited; store reload covered by unit tests
- English and Korean 2-set input-source checks: GUI automation prohibited; physical keyCode lookup
  and fixed ANSI labels covered by code review and unit tests

## Acceptance criteria

- [ ] Cmd+, opens Settings with every action and key: implemented, interactive verification not run
- [ ] Rebinding Pick changes culling and hints immediately and survives restart: implemented;
      persistence and lookup tested, live/restart verification not run
- [ ] Defaults work under English and Korean input: keyCode-only implementation and defaults
      tested, input-source verification not run
- [ ] Conflict move and Restore Defaults behave as described: store tests passed, UI verification not run
- [x] Unit tests cover exact default bindings, test-suite UserDefaults round-trip, corrupt-data
      fallback, conflict reassignment, and keyCode lookup
- [x] `swift build`, `swift test`, and the Xcode app build pass

## Deviations

None

## Risks / concerns

Interactive acceptance remains for Claude or the user to verify. Focus loss cancels recording
so a hidden or inactive Settings window cannot leave culling disabled. Review that interaction
along with the standard Settings menu, English/Korean input, and inline conflict notice.

The successful Xcode build emitted an App Intents metadata warning because the target has no
AppIntents.framework dependency. It did not fail the build.

## Suggested shared-context updates

None
