# T006: Wider, resizable folder tree and Close Folder moved to the File menu

Status: accepted
Owner: codex
Depends on: T005

## Objective

Give the top-left of the window room: the folder tree becomes wider (260 pt default) and
resizable by dragging its divider, and the "Close Folder" toolbar button is removed in favour of a
File menu item "Close Folder" with Command W.

## Why

User feedback (2026-10-19, screenshot): the title bar area above the 200 pt folder tree is
cramped. The traffic lights, the "Close Folder" capsule and the "RawCull" title overflow the tree
column. The user chose: widen + drag-resize the tree, and move Close Folder to the menu.

## Context

- Folder tree width is a fixed `.frame(width: 200)` in `CullingView`. The thumbnail sidebar is a
  fixed 120 pt and stays as is.
- `CullingView` shows the toolbar: `.navigation` "Close Folder" (calls `onCloseFolder`) and
  `.primaryAction` "Finish" (Cmd+Return). Keep Finish in the toolbar.
- `ContentView.closeFolder()` is the existing close flow. Reuse it; do not duplicate its logic.
- Menu commands live in `RawCullApp` (no `.commands` yet). Reaching `ContentView` state from a
  command needs `FocusedValue`/`focusedSceneValue` or an equivalent; pick the idiomatic one.
- Command W normally closes the window. When a folder is open, Command W must close the folder
  instead and keep the window. When no folder is open, the item is disabled and Command W keeps
  its usual window-close behaviour. Verify which menu item AppKit picks for Command W in both
  states (inspect `NSApp.mainMenu` in a quick test or reason from the built menu) and document it.
- All UI strings are localized through `Sources/RawCull/Resources/Localizable.xcstrings`
  (en + ko). "Close Folder" already exists there ("폴더 닫기"). Any new string needs a ko value.
- `.ai/decisions.md` and `AGENTS.md` hold the conventions (FavrenUI tokens, no em dash).

## Relevant files

- `Sources/RawCull/Views/CullingView.swift`
- `Sources/RawCull/App/ContentView.swift`
- `Sources/RawCull/App/RawCullApp.swift`
- `Sources/RawCull/Resources/Localizable.xcstrings` (only if new strings)

## Implementation requirements

1. Folder tree default width 260 pt, user-resizable by dragging the divider between the tree and
   the thumbnail sidebar, clamped to 200...420 pt, with a resize cursor on hover. Persist the width
   (`@AppStorage` is fine). Toggling the tree with its shortcut keeps the chosen width.
2. Remove the "Close Folder" toolbar item.
3. Add "Close Folder" (Command W) to the File menu, enabled only while a folder is open, invoking
   the existing close flow.
4. With no folder open, Command W closes the window as before.

## Non-goals

- Do not change the thumbnail sidebar width, Finish, status bar, photo view, or the Settings window.
- Do not switch to `NavigationSplitView`.

## Acceptance criteria

- [ ] Default tree width 260 pt; dragging the divider resizes within 200...420; width survives relaunch.
- [ ] No "Close Folder" button in the toolbar.
- [ ] File > Close Folder (Command W) closes the folder when one is open; disabled otherwise, and
      Command W then closes the window as before (documented how this was verified).
- [ ] Localization catalog stays complete for ko.
- [ ] `swift build`, `swift test`, and the `xcodebuild` app build pass.

## Required checks

- `swift build`
- `swift test`
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`

## Expected output

Changes in the files above and `.ai/handoffs/T006-handoff.md`.
