# T003: Correct zoom placement at narrow widths and add a top-right minimap

Status: accepted
Owner: codex
Depends on: T002

## Objective

In zoom mode (Space), the photo is always centered and scrolls correctly on both axes, even when
the viewport is narrow. A minimap in the top-right corner shows the whole photo with a rectangle
marking the visible part; clicking or dragging in it pans the zoomed view.

## Why

With a narrow window the fitted size is limited by width, so `fittedHeight * 2` can be smaller
than the viewport height. The scroll view's document (`containerView`) is then shorter than the
clip view, and AppKit pins it to the bottom (non-flipped clip view), so the photo sits off-center
vertically and vertical scrolling behaves wrongly. The user also wants orientation while zoomed.

## Context

- Everything lives in `Sources/RawCull/Views/PhotoView.swift`: `CenteredZoomImageView`
  (representable) and `CenteredZoomScrollView` (`NSScrollView` subclass, `zoomScale = 2`).
- `imageView` frame is the unrotated frame; rotation is a layer transform around its center. The
  displayed (rotated) photo occupies a rect of size `fittedSize * zoomScale` centered in the
  document. Use that displayed rect for minimap mapping, not `imageView.frame`.
- The document and clip views are not flipped: y grows upward. The minimap's top edge must map to
  the photo's top edge.
- `rotationQuarterTurns` can change while zoomed (Z/C); `image` can change from preview to
  detail resolution while zoomed (same photo, bigger image). Neither should break centering or the
  minimap. T001 may rotate cached images in place after Return, which also arrives as a new image.
- Window resizes and toggling the side panels (T, F keys) resize the viewport while zoomed.

## Relevant files

- `Sources/RawCull/Views/PhotoView.swift`

## Implementation requirements

1. Document size per axis = `max(displayedSize, viewportSize)`; the photo is centered inside the
   document. When the photo is smaller than the viewport on an axis it is centered on that axis
   and does not scroll on it.
2. Initial zoom (and image or rotation change) centers on the photo's midpoint, as today.
3. Viewport resize while zoomed keeps the same photo point at the viewport center (clamped),
   instead of jumping to a corner.
4. Minimap overlay, top-right, inset about 12 pt, longest side about 160 pt, aspect ratio of the
   displayed (rotated) photo, the photo drawn rotated like the main view, subtle dark translucent
   background with a thin border and small corner radius, and a white rectangle (with a light
   dimming outside it, optional) showing the visible region clamped to the photo bounds.
5. The rectangle updates live during scroll (trackpad, scroll wheel, scrollers) and on resize.
   Observe the clip view's bounds changes; avoid pushing SwiftUI state on every scroll event
   (an AppKit subview inside the representable is preferred).
6. Click or drag inside the minimap scrolls the main view so that point becomes the viewport
   center (clamped).
7. Hide the minimap if the whole photo is visible on both axes.
8. The minimap must not intercept scrolling or clicks outside its own frame.

## Non-goals

- No zoom levels other than 2x, no pinch zoom, no zoom-to-cursor.
- Do not change the non-zoomed fitted view, key handling, `StatusBar` or `CullingView`.

## Acceptance criteria

- [ ] In a narrow, tall viewport, Space shows the photo vertically and horizontally centered;
      it scrolls horizontally across the full photo and does not scroll vertically when the photo
      is shorter than the viewport.
- [ ] In a wide viewport, Space behaves as before (centered, scrolls both ways as needed).
- [ ] Rotating with Z/C while zoomed keeps the photo centered and the minimap rotated to match.
- [ ] Minimap appears top-right while zoomed, rectangle tracks scrolling, click/drag pans.
- [ ] Resizing the window or toggling panels while zoomed keeps the view centered on the same spot.
- [ ] If practical, pure geometry helpers (document size, visible-rect-to-minimap mapping with
      the non-flipped y axis) are unit tested.
- [ ] `swift build`, `swift test`, and the `xcodebuild` app build pass.

## Required checks

- `swift build`
- `swift test`
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`

## Expected output

Changes in `PhotoView.swift` (helper files are fine; run `xcodegen generate` if added), tests if
any, and `.ai/handoffs/T003-handoff.md`.
