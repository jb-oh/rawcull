# T010: Make thumbnail selection work in the app, and batch rotation

Status: accepted
Owner: codex
Depends on: T009

## Objective

1. Thumbnail multi-selection from T009 does not work in the running app (user report,
   2026-10-19: "선택이 안 되는 것 같아"). Make Shift-click and Command-click selection work and
   be clearly visible.
2. Batch actions include rotation: with 2+ photos selected, rotating and saving applies to every
   selected photo.

## Why

T009 replaced the cell `.onTapGesture` / `.contextMenu` with a transparent AppKit overlay
(`ThumbnailClickTarget` / `ThumbnailClickView` in `ThumbnailSidebar.swift`). Its unit tests call
`mouseDown` and `menu(for:)` directly, so they never prove that real clicks reach that view
through SwiftUI hit testing inside the `ScrollView`/`LazyVStack`. The overlay existed only so
Control-click could toggle; that requirement was dropped (Control-click now opens the context
menu per macOS convention), so it no longer has a reason to exist. Separately, the selected-cell
highlight (1 pt border at 55% primary) is too faint to read as "selected".

## Context

- Selection model, targets and batch decisions in `CullSession` (T009) are correct and tested.
  Keep the model and its rules exactly (see `.ai/tasks/T009-thumbnail-multi-select.md`,
  "Selection model"). This task changes the click plumbing, the visuals and adds rotation.
- Rotation today (single photo): Z/C change `CullingView.rotationQuarterTurns` (a preview-only
  rotation of the current photo); Return (`saveRotation`) writes it with
  `RotationWriter.apply(quarterTurns:to:)` off the main actor, guarded by
  `imageLoader.beginRotationWrite(for:)`, then `imageLoader.applySavedRotation` (rotates cached
  thumbnail/preview in place) or `cancelRotationWrite` on failure, and shows a `RotationFeedback`
  badge. `resetView()` runs on every `currentIndex` change and zeroes the pending rotation.
- JPEG/HEIC/TIFF/PNG are rotated losslessly in place; RAW gets a `.xmp` sidecar
  (`.ai/decisions.md`). Writes are user-triggered and atomic; keep it that way.

## Implementation requirements

### A. Click handling that provably works

1. Remove `ThumbnailClickTarget` / `ThumbnailClickView`. Go back to SwiftUI on the cell:
   `.onTapGesture` that reads the current modifier state (`NSEvent.modifierFlags`) and calls
   `ThumbnailSidebar.select(index:modifiers:in:)` (Shift = range, Command = toggle, Control is
   not a selection modifier), and `.contextMenu` whose content is built from
   `session.contextMenuTargets(index:)` at open time. Control-click and right-click open that
   menu natively; opening it must not change selection or the current photo.
2. Keep the menu items from T009 (Pick / Reject / Unmark with counts, separator, Reveal in
   Finder) and add rotation items, see C.
3. Add a test that proves a real click path: host `ThumbnailSidebar` (with the environment it
   needs) in an `NSHostingView` inside an offscreen `NSWindow`, deliver synthetic
   `leftMouseDown`/`leftMouseUp` events through `window.sendEvent` at a cell's location, with no
   modifiers, with `.command` and with `.shift`, and assert the session selection. If SwiftUI does
   not deliver synthetic events to `onTapGesture` in a test process, say so in the handoff with
   what you observed, keep the model-level tests, and do not fake the assertion.

### B. Visible selection

4. Selected (non-current) cells get an obvious highlight across the whole cell (image and file
   name), for example a `FavrenColors.primary` tinted background around the cell plus a 2 pt
   border at reduced opacity. The current cell keeps the strongest look (full primary 2 pt
   border) and is also visibly part of the selection. Use FavrenUI tokens only. Rejected cells
   keep their dimming without hiding the highlight.

### C. Batch rotation

5. Keys with 2+ selected: Z/C still change the single pending `rotationQuarterTurns`, which now
   previews on the main photo and on every selected thumbnail (rotate the thumbnail image in the
   cell, preview only). Return writes that rotation to every target (`session.actionTargets`).
   With one selected, behaviour is unchanged.
6. Changing selection (click, Shift/Command-click, navigation, Escape) resets the pending
   rotation, matching the existing `resetView()` rule. Make sure a Shift/Command-click that moves
   `currentIndex` does not leave a stale preview rotation on thumbnails.
7. Context menu: add "Rotate Left" and "Rotate Right" (90 degrees) items that immediately write
   the rotation to the menu's targets (one or many), no Return needed.
8. Batch write: sequentially (or with bounded concurrency) off the main actor, per file
   `beginRotationWrite` → `RotationWriter.apply` → `applySavedRotation`, or
   `cancelRotationWrite` on failure. Continue past failures. Skip files whose
   `beginRotationWrite` returns false (a write already in flight) and count them as not saved.
   Afterwards subtract the saved turns from the pending rotation like `saveRotation` does today,
   so rotating again during the write stays consistent.
9. Feedback badge after a batch: "Rotation saved for N photos" / "사진 N장 회전 저장 완료",
   and when some fail "Saved N, failed M" style wording with ko ("N장 저장, M장 실패"), using
   plural-aware catalog entries. Show it regardless of which photo is current. Single-photo
   messages stay as they are.
10. All new strings in `Localizable.xcstrings` with complete ko; `LocalizationTests` covers the new
    plural strings. Rotate Left/Right ko: "왼쪽으로 회전" / "오른쪽으로 회전".

## Non-goals

- No change to the selection rules, Move Files, the folder tree, the photo view zoom or Settings.
- No new rebindable shortcuts; Z/C/Return keep their current bindings.
- No Command-A, Shift+arrow or drag selection.

## Acceptance criteria

- [ ] AppKit click overlay removed; cells use `.onTapGesture` + `.contextMenu`; Control-click is
      not a selection modifier.
- [ ] Hosted-window click test passes, or the handoff documents exactly why synthetic events do
      not reach SwiftUI in tests.
- [ ] Selected cells are clearly highlighted (describe the exact styling in the handoff).
- [ ] With 2+ selected, Z/C preview rotation on the main photo and all selected thumbnails;
      Return writes all targets; menu Rotate Left/Right write immediately; partial failures are
      reported; pending rotation resets on selection changes.
- [ ] Unit tests cover the batch rotation writer logic against temp JPEG files (for example a
      testable helper that rotates a list of URLs and returns saved/failed counts), including a
      failure in the middle of the list.
- [ ] Catalog complete for ko; `swift build`, `swift test`, and the `xcodebuild` app build pass.

## Required checks

- `swift build`
- `swift test`
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`
- `xcodegen generate` if you add or remove source files.

## Expected output

Changes in `ThumbnailSidebar`, `CullingView`, possibly `CullSession`/`ImageLoader`, the catalog,
tests, and `.ai/handoffs/T010-handoff.md`.
