# Move All Folders Design

Date: 2026-09-15. Extends the folder tree panel (see
`2026-09-15-folder-tree-panel-design.md`).

## Goal

From the summary screen, move every decided photo under the root folder in one
step, so the user does not have to Finish each folder separately.

## Behaviour

- Each folder keeps its own `.rawcull-session.json`, `Picks/` and `Rejects/`. The
  file format does not change.
- "Move All Folders" walks the root and every descendant folder (using
  `FolderScanner.folderTree`). For each folder that has a session file and at least
  one decided photo, it moves that folder's picks and rejects into that folder's
  own `Picks/` and `Rejects/` (via the existing `FileMover.moveFiles`) and then
  deletes that folder's session file. Folders without a session, or whose session
  has no decided photos, are left untouched.
- Decisions for files that no longer exist in the folder are ignored.
- Before walking, the current in-memory session is flushed so the folder being
  reviewed is included.
- The summary screen shows, below the current folder's counts, the totals across
  all folders under the root (folders with sessions, picks, rejects, undecided),
  computed in the background when the screen appears.
- Buttons: `Go Back`, `Move Files` (current folder only, unchanged), and
  `Move All Folders` (disabled when the totals have no picks or rejects).
- Completion message: "N picks and M rejects moved across K folders". `Continue`
  behaves as before (reload current folder, rebuild tree).
- Progress is reported over the total number of decided files across all folders.

## Code

- `Models/SavedSession.swift` (new): the `SavedSession` struct moves out of
  `CullSession.swift` unchanged, with helpers `SavedSession.url(in:)` and
  `SavedSession.load(from:)`. `CullSession` uses them.
- `FileMover`:
  - `struct SessionTotals { folders, picks, rejects, undecided }`
  - `struct TreeMoveResult { folders, picks, rejects }`
  - `static func sessionTotals(rootURL:) -> SessionTotals`
  - `static func moveAllSessions(rootURL:progress:) throws -> TreeMoveResult`
- `SummaryView` gains `rootURL: URL?`, the totals block and the new button.
- `ContentView` passes `rootURL` to `SummaryView`.

## Errors

`moveAllSessions` stops at the first failing move and throws `FileMover.MoveError`;
folders already processed stay moved and their session files stay deleted. The
summary screen shows the error as it does for `Move Files`.

## Testing

`FileMoverTests` (new, swift-testing) builds a temp tree with two session folders,
one nested, one folder without a session, and one session with only undecided
photos, then checks moved paths, untouched files, deleted session files, returned
counts, and the final progress callback. `sessionTotals` is checked on the same
fixture before moving. Existing `CullSessionTests` must still pass after the
`SavedSession` extraction.
