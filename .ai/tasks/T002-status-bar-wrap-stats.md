# T002: Status bar that wraps at narrow widths and shows folder stats

Status: accepted
Owner: codex
Depends on: T001

## Objective

Rebuild `StatusBar` so nothing is ever squeezed: at narrow widths its groups wrap onto extra
lines. Make the folder's totals (photos, picks, rejects, left) clearly labeled and always visible.

## Why

At narrow window widths the single `HStack` compresses `FavrenKeyCap`s into thin empty pills and
truncates labels (user screenshot). The user also wants to check, at any time while culling, how
many photos the folder has and how many are picked and rejected. Today only two bare numbers with
icons are shown, and they get squeezed too.

## Context

- `CullSession` already tracks `pickCount`, `rejectCount`, `undecidedCount` and `count`.
- `StatusBar` is used once, in `CullingView` (under the photo, full width of the main column).
- T001 may have added a Return / "save rotation" hint. Keep it.
- macOS 14 target: the SwiftUI `Layout` protocol and `ViewThatFits` are available.

## Relevant files

- `Sources/RawCull/Views/StatusBar.swift`
- `Sources/RawCull/Views/CullingView.swift` (call site only)

## Implementation requirements

1. Split the content into unbreakable units, each rendered at its ideal size (never compressed):
   - position: `‹ 12 / 142 ›` and the decision badge;
   - stats: `142 photos`, picks (`checkmark.circle.fill`, success tone, `23 picks`), rejects
     (`xmark.circle.fill`, danger tone, `8 rejects`), `111 left` (secondary style). Use singular
     forms for 1 (`1 photo`, `1 pick`, `1 reject`). `left` = undecided count;
   - each keyboard hint pair is its own unit: `A accept`, `S unmark`, `D reject`, `Z X C view`,
     `Space zoom`, plus `Return save rotation` if present.
2. Wide windows: one line, position and stats leading, hints trailing (as today).
3. Narrow windows: units wrap onto further lines using a wrapping (flow) `Layout`, left aligned,
   consistent horizontal and line spacing. The bar grows in height; the photo above shrinks.
   A `ViewThatFits` between the one-line layout and the flow layout is an acceptable approach.
4. Stats stay on the first line whenever the position unit plus stats fit; hints wrap first.
5. Pass `undecidedCount` from `CullingView`. Keep FavrenUI tokens and the `.bar` background.

## Non-goals

- No changes to `CullSession`, culling keys or the folder tree.
- Do not edit `PhotoView.swift` (T003 owns it).
- No new settings or toggles.

## Acceptance criteria

- [ ] At any width from 360 pt up no key cap or label is compressed or truncated; units wrap.
- [ ] Wide window renders on one line, visually close to the current bar.
- [ ] Stats show total, picks, rejects and left with words, correct singular/plural.
- [ ] Counts update live when marking A/S/D.
- [ ] `swift build`, `swift test`, and the `xcodebuild` app build pass.

## Required checks

- `swift build`
- `swift test`
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`

## Expected output

Changes in `StatusBar.swift` (a new layout file is fine; run `xcodegen generate` if you add one),
the call site in `CullingView.swift`, and `.ai/handoffs/T002-handoff.md`.
