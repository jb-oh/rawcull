# Decisions

## 2026-10-18: How rotation is written to files

- **Decision:** ImageIO-writable formats get their orientation metadata rewritten in place with
  `CGImageDestinationCopyImageSource` (lossless, atomic replace). RAW formats get a
  `<basename>.xmp` sidecar carrying `tiff:Orientation`, merged into any existing sidecar.
- **Reason:** ImageIO cannot write RAW containers. XMP sidecars are what Lightroom, Bridge and
  Capture One read. The user chose this option explicitly.
- **Alternatives:** in-place only with RAW unsupported; storing rotation only in
  `.rawcull-session.json` (invisible to other apps).
- **Consequences:** `ImageLoader` must apply the sidecar orientation; `FileMover` must move
  sidecars with their RAW files.

## 2026-10-18: Shortcuts match physical keys

- **Decision:** culling shortcuts are stored as keyCodes (no modifiers) in `UserDefaults`, with
  labels from a fixed ANSI table.
- **Reason:** keyCode matching works identically under English and Korean input sources, which
  removes the hand-maintained `ㅁ/ㄴ/ㅇ` alias list and makes rebinding layout-independent.
- **Alternatives:** matching characters (breaks under Korean input), supporting modifiers
  (collides with menu shortcuts, more UI).

## 2026-10-18: Language override uses AppleLanguages

- **Decision:** the in-app language picker writes the app's `AppleLanguages` default and asks for
  a restart (with a Restart Now button).
- **Reason:** it is the standard macOS per-app language mechanism and also localizes system
  menus. Live switching via `\.locale` does not cover `String(localized:)` or AppKit menus.

## 2026-10-19: Picks/ and Rejects/ folders carry their decision

- **Decision:** a folder named exactly `Picks` or `Rejects` inside another folder defaults its
  photos to pick or reject. Move Files there sends opposite decisions to the sibling folder and
  undecided photos back to the parent.
- **Reason:** after Move Files the folder location is the decision and the source session is
  deleted, so these folders looked "undecided" to the user. The user chose this option.
- **Alternatives:** keep behaviour and only label sorted folders; hide them from the tree.
