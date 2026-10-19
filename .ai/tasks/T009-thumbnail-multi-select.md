# T009: Multi-selection in the thumbnail sidebar

Status: accepted
Owner: codex
Depends on: T008

## Objective

Users can select several thumbnails (Shift-click for a contiguous range, Command-click to
toggle single items) and apply Pick, Reject, Unmark and Reveal in Finder to all
of them at once, from the keyboard shortcuts or the thumbnail context menu.

## Why

User request (2026-10-19): culling a burst one photo at a time is slow. They want Finder-style
multi-selection in the thumbnail bar and batch actions.

## Context

- `CullSession` (`Sources/RawCull/Models/CullSession.swift`) owns `items`, `currentIndex`,
  counts and a debounced save. `markPick/markReject/unmarkCurrent` call `applyDecision`, which only
  touches the current item. `load` and `reset` start a folder fresh.
- `ThumbnailSidebar` (`Sources/RawCull/Views/ThumbnailSidebar.swift`): `LazyVStack` of
  `ThumbnailCell`, `.onTapGesture` jumps, `.contextMenu` has "Reveal in Finder" (T008: right-click
  must not change the current photo).
- `CullingView.handleKeyDown` maps physical keys to `CullAction` through `KeyBindingStore`; it
  ignores events that carry Command, Control, Option or Shift. Keep that.
- `StatusBar` shows position and folder stats in a wrapping `StatusBarFlowLayout`.
- Strings go through `Sources/RawCull/Resources/Localizable.xcstrings` with complete `ko`
  (`LocalizationTests` enforces it). Wording: Pick 픽, Reject 리젝, Unmark 표시 해제 (reuse the
  catalog entries), "Finder에서 보기". No em dash, no
  trailing periods on labels.
- **Modifiers follow macOS convention:** Command-click toggles, Shift-click extends. Control-click
  is the macOS secondary click and must keep opening the context menu (no selection change). Do
  not add Control-click toggling. (The user corrected an earlier draft of this task on this point.)

## Selection model (binding, implement exactly)

State lives in `CullSession`: a set of selected item ids (`PhotoItem.id`) plus an anchor index.
Invariant: whenever `items` is non-empty, the selection contains the current item.

- **Plain click** on cell i: selection = {i}, current = i, anchor = i.
- **Shift-click** on cell i (with or without Command): selection = every index between
  anchor and i inclusive (replaces the previous selection), current = i, anchor unchanged.
- **Command-click** on cell i:
  - i not selected: add it, current = i, anchor = i.
  - i selected and the selection has 2+ items: remove it. If i was current, current moves to the
    nearest remaining selected index (lower index wins a tie). Anchor = the new current.
  - i is the only selected item: no change.
- **Keyboard navigation** (previous/next actions), `jumpTo`, `load` and `reset`: selection
  collapses to {current}, anchor = current.
- **Escape** (keyCode 53, no modifiers) while 2+ items are selected collapses the selection to
  {current} and is consumed. With a single selection Escape is not consumed (return false).
- **Targets** of a batch action: the selected items when the selection has 2+ items, otherwise
  the current item only.

## Implementation requirements

1. Put the selection logic in `CullSession` (or a small value type it owns) so it is unit
   testable without views. Expose what the views need: whether an index is selected, the selection
   count, the click operations above, and the target list.
2. Pick / Reject / Unmark (keyboard actions and context menu) apply the decision to every target,
   update counts correctly (items that already have that decision are unchanged), and schedule one
   save. Current behaviour for a single selection stays identical.
3. Context menu on a cell:
   - If the clicked cell is selected and the selection has 2+ items, the menu acts on the whole
     selection; otherwise it acts on the clicked cell only. Opening the menu never changes the
     selection or the current photo.
   - Items: Pick, Reject, Unmark, a separator, Reveal in Finder. When acting on 2+ photos, the
     decision items say how many photos they affect (for example "Pick 3 Photos" /
     "3장 픽하기"; use plural-aware catalog entries like the existing count strings).
   - Reveal in Finder selects all target files in one Finder window.
4. Thumbnail cells show selection: the current item keeps its 2 pt primary border; other selected
   items get a clearly visible but weaker highlight using FavrenUI tokens (for example
   `FavrenColors.primary` at reduced opacity as a background or border). Rejected cells keep their
   dimming; the selection highlight must stay visible on them.
5. The status bar shows the selection count ("3 selected" / "3장 선택됨", plural-aware) only
   while 2+ items are selected, in the same flow layout so narrow widths still wrap.
6. Keep T008 behaviour: file name caption, tooltip with the full name, lazy loading, scroll to the
   current item. Shift/Command clicks must not scroll the list unexpectedly beyond the
   existing scroll-to-current behaviour.
7. Rotation, zoom and Return (save rotation) keep acting on the current photo only.

## Non-goals

- No batch rotation, no Shift+arrow range extension, no Command-A select all, no drag selection.
- No undo system.
- No changes to Move Files, the folder tree, the photo view or the Settings window.
- No new keyboard shortcuts in `KeyBindingStore` (Escape is handled directly, not rebindable).

## Acceptance criteria

- [ ] Unit tests in `Tests/RawCullTests/CullSessionTests.swift` (or a new test file) cover: plain
      click, Shift range from the anchor in both directions, Command toggle add/remove, removing the
      current item moves current to the nearest selected index, removing the only item is a no-op,
      navigation and load collapse the selection, batch pick/reject/unmark update decisions and
      counts and save once, single-selection behaviour unchanged.
- [ ] Shift-click and Command-click implemented as specified; right-click and Control-click open
      the context menu without changing selection.
- [ ] Context menu items and counts as specified; Reveal in Finder selects all targets.
- [ ] Selected cells and the status bar count visible as specified.
- [ ] Catalog complete for ko; `LocalizationTests` updated for the new plural strings.
- [ ] `swift build`, `swift test`, and the `xcodebuild` app build pass.

## Required checks

- `swift build`
- `swift test`
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`
- Run `xcodegen generate` if you add source files.

## Expected output

Changes in `CullSession`, `ThumbnailSidebar`, `CullingView`, `StatusBar`, the catalog, tests,
and `.ai/handoffs/T009-handoff.md`.
