# T001 Handoff

Status: implemented

## Summary

Implemented persistent rotation on Return and keypad Enter. Writable images use lossless ImageIO metadata copying and atomic replacement. RAW files use merged XMP sidecars. Cached images rotate after a successful write, and stale in-flight decodes cannot overwrite them. Sidecars move with their RAW files.

## Files changed

- `Sources/RawCull/Services/RotationWriter.swift`
  - New orientation composition/delta helpers, RAW detection, sidecar lookup, and atomic metadata writers
- `Sources/RawCull/Services/ImageLoader.swift`
  - Apply RAW sidecar deltas at every decoded size, rotate existing caches, and guard load completion with per-URL revisions and a cache generation
- `Sources/RawCull/Views/CullingView.swift`
  - Handle both Enter keys, save off the main actor, guard concurrent writes, conditionally reset view rotation, and display transient FavrenUI feedback
- `Sources/RawCull/Views/StatusBar.swift`
  - Add the minimal Return/save rotation hint
- `Sources/RawCull/Services/FileMover.swift`
  - Move RAW sidecars and report sidecar failures without rolling back completed photo moves
- `Tests/RawCullTests/RotationWriterTests.swift`
  - Orientation arithmetic, JPEG metadata/pixel preservation, XMP merging, uppercase lookup, and failure preservation tests; shared temporary image fixtures
- `Tests/RawCullTests/ImageLoaderTests.swift`
  - Rotation direction, RAW sidecar delta at all sizes, cache rotation, and controlled in-flight load race tests
- `Tests/RawCullTests/FileMoverTests.swift`
  - RAW sidecar moves for picks/rejects and both extension cases, RAW/JPEG ownership, and sidecar move failure coverage
- `RawCull.xcodeproj/project.pbxproj`
  - Regenerated with the new source file
- `.ai/handoffs/T001-handoff.md`
  - This handoff

## Implementation notes

- `CGImageDestinationCopyImageSource` requires its dedicated `kCGImageDestinationOrientation` option. Destination properties also set the top-level orientation and existing TIFF orientation. The output orientation is verified before replacing the original. There is no pixel re-encoding fallback.
- Existing XMP is parsed, copied into mutable metadata, and updated only at `tiff:Orientation`. Invalid XMP fails without overwriting the sidecar. Tests verify preservation of `xmp:Rating` and a custom namespace property.
- Sidecar lookup reads the stored directory entry spelling. On case-insensitive Mac volumes, `fileExists` alone would return a lowercase URL for an existing uppercase `.XMP`.
- The loader pauses new decodes for the URL during writes. Beginning a write invalidates older decode revisions without clearing visible images. Completion rotates all cached sizes and resumes missing loads. Failed writes retain cached pixels. A cache generation rejects pre-folder-switch decodes. Write barriers survive folder switches and also prevent concurrent writes from a recreated culling view.
- RGB image rotation retains the source color space. RAW sidecars contribute only the rotation delta, preserving the decoded image's mirroring.
- Sidecar move failures follow existing stop-on-first-error semantics. The photo remains moved, the source sidecar remains available, and a `MoveError` names the sidecar.
- `PhotoView.swift`, session serialization, `AGENTS.md`, and existing `.ai/` files were not edited. No commit was made.

## Validation

### Passed

- `xcodegen generate`: regenerated the project; its diff adds only RotationWriter source references
- `swift build`: final run exited 0; log at `/tmp/rawcull-T001-swift-build.log`
- `swift test`: final run exited 0; 34 tests in 5 suites passed, including 40 orientation combinations; log at `/tmp/rawcull-T001-swift-test.log`
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`: final run exited 0 with `BUILD SUCCEEDED`; log at `/tmp/rawcull-T001-xcodebuild.log`
- `git diff --check`: passed
- Final self-review: inspected all changed implementation, tests, and generated project changes

### Failed

- No failures remain in final required checks. Earlier build/test attempts found a CGRect numeric-type error, a nested test-macro error, incorrect uppercase sidecar URL spelling, and color-space differences in rotation tests. These were corrected before the passing runs.
- The initial sandboxed `swift build` failed because `sandbox-exec` could not apply its sandbox. Required Swift/Xcode checks were subsequently run successfully with approved escalation.

### Not run

- Real camera RAW and external editor interoperability checks: the scoped tests use fake RAW files and JPEG payloads with RAW extensions to exercise dispatch and embedded-orientation handling

### Blocked

- Interactive Return/keypad Enter, no-beep, visual continuity, and transient-feedback checks: the computer-use tool returned `Computer Use was not approved to use RawCull`. No UI actions were performed. These behaviors were inspected in code, and cache behavior was tested, but interactive results are not claimed.

## Acceptance criteria

- [x] Composition covers all 8 orientations with turns -1, 1, 2, 3, 5; delta round-trips
- [x] Temporary JPEG reads orientation 6 and then 3; pixel dimensions and decoded pixels are unchanged; no temporary file remains
- [x] Fake `x.cr3` creates `x.xmp` with orientation 6; existing orientation is composed and other XMP properties survive
- [x] `sidecarURL(for:)` finds the exact uppercase `X.XMP` path
- [x] Picked RAW moves with its sidecar; picked JPEG leaves the paired RAW sidecar alone
- [ ] Return with rotation writes and stays visually unchanged: implemented; interactive verification blocked as described above. Cache rotation and stale-load protection passed automated tests
- [ ] Return with no rotation does nothing and does not beep: implemented by the no-rotation guard and consumed key event; interactive verification blocked
- [x] `swift build`, `swift test`, and the Xcode app build pass

## Deviations

Interactive verification could not be completed because computer-use access was not approved. No implementation scope deviations.

## Risks / concerns

- Claude should verify the two interactive acceptance criteria, feedback fading, and the keyboard hint at the intended window width.
- Actual camera RAW containers and external photo editors were not exercised.
- If a sidecar move fails, existing FileMover semantics leave the photo moved and report the sidecar. The photo/sidecar pair is not a transactional move.

## Suggested shared-context updates

- XMP lookup must preserve the directory entry's actual extension case, even on case-insensitive volumes.
- ImageIO lossless copy uses `kCGImageDestinationOrientation`; ordinary image-property keys alone are insufficient as copy options.

## Correction 1

Status: implemented

- `RotationWriter.sidecarOrientation(for:)` now reads `<base>.xmp`, then `<base>.XMP`, directly. The RAW decode path no longer calls `sidecarURL(for:)` or lists the directory.
- Exact-spelling lookup remains in `sidecarURL(for:)` for writes and FileMover. It lists the directory only after a direct `fileExists` check finds a sidecar.
- Added `sidecarOrientationReadsUppercaseXMP`, which reads orientation 6 from `X.XMP`. The existing uppercase exact-spelling test still passes.
- After a successful write on the same URL, `CullingView` now sets `rotationQuarterTurns = RotationWriter.normalizedTurns(rotationQuarterTurns - turns)`. Further rotation entered during the write remains relative to the newly rotated cache.
- Reviewed the correction diff. Only `RotationWriter.swift`, `CullingView.swift`, `RotationWriterTests.swift`, and this appended section changed in this correction. No commit was made.

Validation:

- Passed: `swift build`, exited 0. Log: `/tmp/rawcull-T001-correction1-swift-build.log`
- Passed: `swift test`, exited 0; 35 tests in 5 suites passed. Log: `/tmp/rawcull-T001-correction1-swift-test.log`
- Passed: `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`, exited 0 with `BUILD SUCCEEDED`. Log: `/tmp/rawcull-T001-correction1-xcodebuild.log`
- Passed: `git diff --check`
- Failed: none
- Not run: interactive UI checks; the previously reported computer-use access restriction remains
