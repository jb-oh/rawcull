# T001: Apply the on-screen rotation to the photo file with Return

Status: accepted
Owner: codex
Depends on: None

## Objective

When the user has rotated the current photo with Z/C (`rotationQuarterTurns != 0` in
`CullingView`) and presses Return, write that rotation to the file: orientation metadata in place
for writable formats, an XMP sidecar for RAW. RawCull then shows the photo rotated from the file
itself, and sidecars travel with their RAW when files are moved.

## Why

Rotation today is view-only and is lost on navigation. Users want the fix to stick in the file
so other apps (Preview, Lightroom) see it too. See `.ai/decisions.md` (2026-10-18).

## Context

- `rotationQuarterTurns` counts clockwise quarter turns (C = +1, Z = -1, mod 4).
- EXIF orientation under one clockwise quarter turn of the displayed image:
  non-mirrored cycle `1 → 6 → 3 → 8 → 1`, mirrored cycle `2 → 7 → 4 → 5 → 2`.
  Missing or invalid orientation counts as 1.
- `ImageLoader.loadImage` uses `kCGImageSourceCreateThumbnailWithTransform`, so the embedded
  orientation is already honored for in-place edits. A RAW's sidecar is not: the loader must
  rotate the decoded image by the quarter-turn delta from the embedded orientation to the sidecar
  orientation (rotation part only; mirroring is never changed by RawCull).
- `CullingView.handleKeyDown` ignores events with command/control/option, so plain Return is
  free (Cmd+Return is the Finish toolbar shortcut). Return is keyCode 36, keypad Enter is 76.
- The app is not sandboxed; writing next to photos is allowed.
- Sidecar name: same directory, same basename, extension `xmp`. Reuse an existing sidecar if one
  exists with `xmp` or `XMP`. Only RAW files get sidecars; a RAW+JPEG pair `IMG_1.CR3`/`IMG_1.JPG`
  means `IMG_1.xmp` belongs to the RAW.

## Relevant files

- `Sources/RawCull/Services/RotationWriter.swift` (new): file-writing service.
- `Sources/RawCull/Services/ImageLoader.swift`: decoding and caches.
- `Sources/RawCull/Views/CullingView.swift`: key handling, rotation state, feedback.
- `Sources/RawCull/Services/FileMover.swift`: `moveFiles` must move sidecars.
- `Tests/RawCullTests/FileMoverTests.swift`, `FolderScannerTests.swift`: temp-dir test pattern.

## Implementation requirements

1. Add `RotationWriter` (struct, static functions, `nonisolated`/Sendable-safe) with at least:
   - a pure orientation composition function (EXIF value + clockwise quarter turns → EXIF value),
     correct for all 8 values and negative or >4 turn counts;
   - a pure delta function (from orientation, to orientation → clockwise quarter turns);
   - `sidecarURL(for:)` that finds an existing `.xmp`/`.XMP` or returns the default `.xmp` URL;
   - `apply(quarterTurns:to:) throws` that routes by type: RAW (`UTType.rawImage` conformance)
     → sidecar; otherwise in-place.
2. In-place path: read current orientation from the source, compose, write with
   `CGImageDestinationCopyImageSource` setting `kCGImagePropertyOrientation` (and the TIFF
   dictionary orientation if present) to a temp file in the same directory, then atomically
   replace the original (`FileManager.replaceItemAt`). If the format cannot be copied this way,
   throw a descriptive error; never leave a temp file behind; never re-encode pixels.
3. Sidecar path: current orientation = existing sidecar `tiff:Orientation` if present, else the
   RAW's embedded orientation, else 1. Compose, then write `tiff:Orientation` using
   `CGImageMetadata` (`CGImageMetadataCreateFromXMPData` for an existing sidecar,
   `CGImageMetadataSetValueWithPath`, `CGImageMetadataCreateXMPData`), preserving all other
   existing XMP content. Write atomically.
4. `ImageLoader`: when decoding a RAW that has a sidecar with `tiff:Orientation`, rotate the
   decoded `CGImage` by the delta from embedded to sidecar orientation. Applies to thumbnail,
   preview and detail sizes.
5. `ImageLoader`: add an API used after a successful write that rotates the already cached
   thumbnail/preview/detail images for that URL by the same quarter turns (so the screen does not
   flash or reload), and that guarantees an in-flight load for that URL started before the write
   cannot later insert a stale, unrotated image (for example a per-URL revision counter checked
   before caching, or invalidation plus reload).
6. `CullingView`: Return / keypad Enter with `rotationQuarterTurns != 0` captures the current
   URL and turns, runs the write off the main actor, and on success updates the loader caches and
   resets `rotationQuarterTurns` to 0 only if the user is still on that photo with the same
   rotation (otherwise just update caches). Return with no rotation is swallowed (no beep) and
   does nothing. Ignore Return while a write for the same photo is already running.
7. Feedback: show a small transient message over the photo area ("Rotation saved", or for RAW
   "Rotation saved to <name>.xmp", or the error text on failure), FavrenUI styling, fading after
   about 1.5 s. Keep it in `CullingView` (do not edit `PhotoView.swift`; another task owns it).
8. `FileMover.moveFiles`: when moving a RAW item, also move its existing sidecar into the same
   destination folder. Sidecar move failure must not lose the photo move; report it as a
   `MoveError` only if it is consistent with existing error handling, otherwise skip silently and
   leave a comment explaining why.
9. Add `Return` to the keyboard hints only if it fits the existing hint style; T002 rebuilds the
   status bar, so a minimal entry (`FavrenKeyCap("Return")` + "save rotation") is enough.
10. Run `xcodegen generate` after adding the new source file so `RawCull.xcodeproj` includes it.

## Non-goals

- Do not edit `PhotoView.swift` or restyle `StatusBar.swift` beyond requirement 9.
- No undo for written rotation (pressing Z/C and Return again is the undo).
- No batch rotation of multiple photos. No crop or mirroring.
- Do not change `.rawcull-session.json` format.

## Acceptance criteria

- [ ] Unit tests: composition for all 8 orientations × turns -1, 1, 2, 3, 5; delta round-trips.
- [ ] Unit test: a JPEG created in a temp dir (orientation 1) rotated by 1 turn reads back
      orientation 6; rotating that by 1 more reads 3; pixel dimensions unchanged; no temp file left.
- [ ] Unit test: sidecar path on a fake `x.cr3` creates `x.xmp` with `tiff:Orientation` 6; an
      existing sidecar with another property (for example `xmp:Rating` 3) keeps that property and
      gets the new orientation composed from its previous orientation.
- [ ] Unit test: `sidecarURL(for:)` finds an uppercase `X.XMP`.
- [ ] Unit test: `FileMover.moveFiles` moves a picked `x.cr3` together with `x.xmp`, and does not
      move `x.xmp` with a picked `x.jpg`.
- [ ] Return with rotation writes the file and the view stays visually the same (cache rotated,
      rotation reset). Return without rotation does nothing and does not beep.
- [ ] `swift build`, `swift test`, and the `xcodebuild` app build pass.

## Required checks

- `swift build`
- `swift test`
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`

## Expected output

New `RotationWriter.swift` and its tests, changes in `ImageLoader`, `CullingView`, `FileMover`,
regenerated `RawCull.xcodeproj`, and `.ai/handoffs/T001-handoff.md`.
