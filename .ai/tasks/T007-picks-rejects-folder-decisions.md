# T007: Photos inside Picks/ and Rejects/ show their folder's decision

Status: accepted
Owner: codex
Depends on: T008

## Objective

When the user opens a `Picks/` or `Rejects/` folder (the folders Move Files creates), photos
default to pick or reject instead of undecided. Changing a decision there and running Move Files
re-sorts them: to the sibling folder for the opposite decision, or back to the parent folder for
undecided.

## Why

User report (2026-10-19): photos already moved into `Picks/` showed as "미결정", which looked like
lost decisions. Cause: after Move Files the folder location is the decision and the source
folder's `.rawcull-session.json` is deleted; `Picks/` has no session, so everything loads as
undecided. The user chose "folder location is the decision" (see `.ai/decisions.md`, 2026-10-19).

## Context

- Decisions load in `CullSession.load(folderURL:fileURLs:)`: saved decision by filename, else
  `.undecided`.
- `FileMover.moveFiles(items:folderURL:progress:)` creates `<folder>/Picks` and `<folder>/Rejects`
  and moves decided items there, plus RAW `.xmp` sidecars (T001). Undecided items stay.
  `FileMover.moveAllSessions` walks the whole tree (Picks/ and Rejects/ subfolders included) and
  only processes folders that have a session file. `sessionTotals` counts the same folders.
- `SummaryView.moveFiles()` calls `FileMover.moveFiles`, deletes the session file and shows
  "N moved to Picks/, M moved to Rejects/".
- All UI strings go through `Sources/RawCull/Resources/Localizable.xcstrings` with complete `ko`.
  Wording: Pick 픽, Reject 리젝, Undecided 미결정. No em dash, no trailing periods on labels.

## Definitions

- A **sorted folder** is a folder named exactly `Picks` or `Rejects` (case-sensitive, matching
  what `FileMover` creates) that has a parent folder. Its **folder decision** is `.pick` or
  `.reject`. Its **parent** is the folder that contains it; its **sibling** is
  `<parent>/Rejects` for `Picks` and `<parent>/Picks` for `Rejects`.

## Implementation requirements

1. One shared helper (for example on `FileMover` or a small `SortedFolder` type) identifies sorted
   folders and their folder decision, parent and sibling. Use it everywhere below.
2. Loading a sorted folder: a photo's decision is the saved decision if the folder's session has
   one for that filename, otherwise the folder decision. Ordinary folders are unchanged.
3. Moving in a sorted folder (single-folder Move Files and `moveAllSessions` alike):
   - decision equal to the folder decision: stays, not counted as moved;
   - the opposite decision: moves to the sibling folder (create it if missing);
   - undecided: moves back to the parent folder;
   - RAW sidecars move with their photo exactly as in the ordinary path;
   - destination name collisions behave like the existing path (stop with the existing
     `MoveError`), never overwrite.
   Never create `Picks/Picks`, `Picks/Rejects`, `Rejects/Picks` or `Rejects/Rejects`.
4. The move result must report the three outcomes so the summary can say what happened in
   sorted folders, for example "2 moved to Rejects/, 1 moved back to <parent name>/" (ko e.g.
   "2장 → Rejects/, 1장 → <부모 폴더>/로 되돌림"). Ordinary folders keep their current message.
   `moveAllSessions` totals stay meaningful (count opposite-decision moves under picks or rejects
   by the destination, and add a returned-to-parent count).
5. After a sorted-folder move, delete its session file like the ordinary path, and make the tree
   rebuild show the destination folders (reuse the existing continue/rebuild flow).
6. `sessionTotals` and the summary's pick/reject counts for a sorted folder use the same
   defaults as loading (a `Picks/` folder with a session but no entry for a file counts that file
   as a pick).

## Non-goals

- No change to ordinary folders' behaviour or messages.
- No detection of user-made folders by any rule other than the exact names above.
- No thumbnail sidebar or toolbar changes (other tasks own them).

## Acceptance criteria

- [ ] Opening `X/Picks` with no session shows every photo as pick; `X/Rejects` as reject.
- [ ] In `X/Picks`, marking one reject and one undecided then Move Files moves them to
      `X/Rejects/` and `X/` respectively; the rest stay; sidecars follow; no nested folders.
- [ ] Same through `moveAllSessions` on a tree containing `X/Picks` with a session.
- [ ] Summary message in sorted folders describes the moves; ko translations complete.
- [ ] Unit tests cover loading defaults, single-folder sorted moves, tree moves, collisions and
      `sessionTotals` for sorted folders, using temp directories like `FileMoverTests`.
- [ ] `swift build`, `swift test`, and the `xcodebuild` app build pass.

## Required checks

- `swift build`
- `swift test`
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`

## Expected output

Changes in `CullSession`, `FileMover`, `SummaryView`, the catalog, tests, and
`.ai/handoffs/T007-handoff.md`.
