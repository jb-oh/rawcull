# Requirements (2026-10-18)

User feedback on the culling screen, normalized.

1. **Apply rotation to the file.** After rotating with Z/C, pressing Return (or keypad Enter)
   writes the rotation to the photo itself.
   - JPEG, HEIC, TIFF, PNG and other ImageIO-writable formats: change only the orientation
     metadata of the original, losslessly (no pixel re-encode). Atomic replace.
   - RAW formats (UTType conforming to `public.camera-raw-image`, DNG included): write or update
     a Lightroom-style XMP sidecar `<basename>.xmp` with `tiff:Orientation`. Preserve any other
     content already in an existing sidecar. RawCull itself must honor the sidecar orientation.
   - The sidecar moves with its RAW into `Picks/` or `Rejects/`.
2. **Status bar must not get crushed at narrow widths.** Wrap onto extra lines instead of
   squeezing key caps and text (screenshot showed key caps collapsed into thin pills).
3. **Zoom (Space) at narrow widths:** the zoomed photo must be centered and scroll correctly
   vertically and horizontally. Today the vertical position is off when the window is narrow.
4. **Minimap in zoom mode** at the top-right corner showing which part of the photo is visible.
5. **Pick / reject status:** at any time while culling, see the folder's total photo count,
   picks, rejects (and how many are left).

6. **Korean localization** (added mid-session): UI follows the macOS system language
   (Korean or English).
7. **Settings window**: change the app language (System Default / English / 한국어) and
   rebind the culling shortcuts.

## Acceptance

Each task file under `.ai/tasks/` carries its own criteria. Overall done when all five tasks
are accepted, `swift build`, `swift test` and the `xcodebuild` app build pass, and the GUI checks
listed in `.ai/plan.md` are handed to the user.
