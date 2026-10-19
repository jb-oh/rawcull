# T004: Settings window with customizable keyboard shortcuts

Status: accepted
Owner: codex
Depends on: T003

## Objective

Add a standard macOS Settings window (app menu "Settings…", Cmd+,) whose Shortcuts section lets
the user rebind every culling key. The culling screen and the status bar hints follow the
current bindings. T005 later adds a Language section to the same window, so structure it with
room for more sections (for example a `TabView` with a "Shortcuts" tab).

## Why

User request (2026-10-18): a settings menu to change the language and the shortcuts.

## Context

- Today `CullingView.handleKeyDown` matches hardcoded keyCodes plus characters, with Korean
  2-set aliases (`ㅁ`, `ㄴ`, ...). Matching by **keyCode only** (physical key) makes every binding
  work under both the English and Korean input sources, so the alias list goes away.
- Events with command/control/option are passed through untouched; keep that. Bindings are
  plain keys (no modifiers). Shift is not supported either; keep it simple.
- Current default keys (must stay the defaults):
  previous: Left(123), Up(126), H(4); next: Right(124), Down(125), L(37); pick: A(0);
  unmark: S(1); reject: D(2); rotate counter-clockwise: Z(6); reset view: X(7);
  rotate clockwise: C(8); zoom: Space(49); save rotation: Return(36), keypad Enter(76);
  toggle thumbnails: T(17); toggle folder tree: F(3).
- `StatusBar` (rebuilt in T002) shows key caps for some actions; it must show the user's
  current first binding for each hinted action instead of fixed letters.
- macOS 14: SwiftUI `Settings` scene is available in `RawCullApp`.

## Relevant files

- `Sources/RawCull/App/RawCullApp.swift`, `Sources/RawCull/App/ContentView.swift`
- `Sources/RawCull/Views/CullingView.swift` (key handling)
- `Sources/RawCull/Views/StatusBar.swift` (hints)
- new model/service and view files as needed (run `xcodegen generate` after adding files)

## Implementation requirements

1. A `CullAction` enum covering every action above, and a key binding model (keyCode plus a
   display label) with a store that persists to `UserDefaults` (Codable JSON under one key),
   falls back to the defaults when the stored value is missing or undecodable, and supports
   multiple keys per action.
2. A static keyCode → label table for the ANSI keyboard (letters, digits, punctuation, arrows as
   ←↑→↓, Space, Return, Enter, Tab, Delete, Escape is not bindable, F1-F12). Labels never depend
   on the active input source, so a key recorded under the Korean layout shows `A`, not `ㅁ`.
3. One shared store instance injected via the SwiftUI environment into the main window and the
   Settings window, so edits apply immediately without restart.
4. `CullingView.handleKeyDown` resolves keyCode → action through the store. Unbound keys fall
   through (return false) as today. Keep the `loading != nil` swallow behaviour.
5. Settings → Shortcuts: a list of actions with human-readable names and their keys as
   `FavrenKeyCap`s; per action a way to add a key (record mode: next plain key press is
   captured, Escape cancels, keys with cmd/ctrl/option are ignored) and to remove a key; a
   "Restore Defaults" button. While recording, the culling key monitor must not act on the key.
6. Conflicts: assigning a key already bound to another action moves it to the new action and
   tells the user inline which action lost it. An action may end up with no keys; show "None".
7. `StatusBar` hints use the current first key of each hinted action (and hide a hint whose
   action has no key).
8. All new UI strings in plain English via `Text("...")`/`String(localized:)` so T005 can
   localize them; no em dash characters.

## Non-goals

- No language setting (T005). No modifier-key shortcuts. No menu-bar shortcut editing
  (Cmd+Return Finish stays fixed). No import/export of bindings.

## Acceptance criteria

- [ ] Cmd+, opens Settings with a Shortcuts section listing every action with its current keys.
- [ ] Rebinding pick to another key works immediately in the culling screen; old key no longer
      picks; status bar hint updates; the binding survives an app restart.
- [ ] Default keys work under both English and Korean (2-set) input sources by keyCode.
- [ ] Conflict move and Restore Defaults behave as described.
- [ ] Unit tests: default bindings match the table above; store round-trips through a
      test-specific `UserDefaults` suite; corrupt stored data falls back to defaults; conflict
      reassignment; keyCode lookup returns the right action.
- [ ] `swift build`, `swift test`, and the `xcodebuild` app build pass.

## Required checks

- `swift build`
- `swift test`
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`

## Expected output

New binding model/store and Settings view files, changes in `RawCullApp`, `ContentView` (if
needed for injection), `CullingView`, `StatusBar`, tests, regenerated project, and
`.ai/handoffs/T004-handoff.md`.
