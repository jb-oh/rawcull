import AppKit
import FavrenUI
import SwiftUI

struct PhotoView: View {
    let image: NSImage?
    let decision: Decision
    @Binding var isZoomed: Bool
    let rotationQuarterTurns: Int

    @State private var flashColor: Color? = nil

    var body: some View {
        ZStack {
            Color.black

            if let image {
                if isZoomed {
                    CenteredZoomImageView(
                        image: image,
                        rotationQuarterTurns: rotationQuarterTurns
                    )
                } else {
                    GeometryReader { proxy in
                        let fittedSize = fittedDisplaySize(
                            for: image.size,
                            in: proxy.size,
                            rotationQuarterTurns: rotationQuarterTurns
                        )

                        Image(nsImage: image)
                            .resizable()
                            .frame(
                                width: imageFrameSize(
                                    for: fittedSize,
                                    rotationQuarterTurns: rotationQuarterTurns
                                ).width,
                                height: imageFrameSize(
                                    for: fittedSize,
                                    rotationQuarterTurns: rotationQuarterTurns
                                ).height
                            )
                            .rotationEffect(.degrees(Double(rotationQuarterTurns * 90)))
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }
                }
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }

            // Decision flash overlay
            if let flashColor {
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(flashColor, lineWidth: 4)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: decision) { oldValue, newValue in
            guard newValue != .undecided else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                flashColor = newValue == .pick ? FavrenSemantic.success : FavrenSemantic.danger
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.3)) {
                flashColor = nil
            }
        }
    }
}

private struct CenteredZoomImageView: NSViewRepresentable {
    let image: NSImage
    let rotationQuarterTurns: Int

    func makeNSView(context: Context) -> CenteredZoomScrollView {
        let scrollView = CenteredZoomScrollView()
        scrollView.updateImage(image, rotationQuarterTurns: rotationQuarterTurns)
        return scrollView
    }

    func updateNSView(_ nsView: CenteredZoomScrollView, context: Context) {
        nsView.updateImage(image, rotationQuarterTurns: rotationQuarterTurns)
    }
}

private final class CenteredZoomScrollView: NSScrollView {
    private let containerView = NSView()
    private let imageView = NSImageView()
    private let minimapView = ZoomMinimapView()
    private var currentImage: NSImage?
    private var rotationQuarterTurns = 0
    private var shouldCenterOnNextLayout = true
    private var geometry: ZoomGeometry?
    private var photoCenter = CGPoint(x: 0.5, y: 0.5)
    private var isLayingOut = false

    init() {
        super.init(frame: .zero)
        drawsBackground = false
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        borderType = .noBorder

        containerView.frame = .zero
        containerView.wantsLayer = true

        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.frame = .zero
        containerView.addSubview(imageView)
        documentView = containerView

        addSubview(minimapView)
        minimapView.panToPoint = { [weak self] point in
            self?.scrollToPhotoPoint(point)
        }
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateImage(_ image: NSImage, rotationQuarterTurns: Int) {
        let normalizedTurns = ((rotationQuarterTurns % 4) + 4) % 4

        if currentImage !== image {
            currentImage = image
            imageView.image = image
            shouldCenterOnNextLayout = true
        }

        if self.rotationQuarterTurns != normalizedTurns {
            self.rotationQuarterTurns = normalizedTurns
            shouldCenterOnNextLayout = true
        }

        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        guard !isLayingOut else { return }
        isLayingOut = true
        defer { isLayingOut = false }
        super.layout()

        guard let image = currentImage else { return }

        let viewportSize = contentView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let newGeometry = ZoomGeometry(
            imageSize: imageSize,
            viewportSize: viewportSize,
            rotationQuarterTurns: rotationQuarterTurns
        )
        let documentSize = newGeometry.documentSize
        let imageFrameSize = imageFrameSize(
            for: newGeometry.photoRect.size,
            rotationQuarterTurns: rotationQuarterTurns
        )
        let shouldReposition = shouldCenterOnNextLayout || geometry != newGeometry
        geometry = newGeometry
        horizontalScrollElasticity = documentSize.width > viewportSize.width ? .automatic : .none
        verticalScrollElasticity = documentSize.height > viewportSize.height ? .automatic : .none

        if containerView.frame.size != documentSize {
            containerView.frame = NSRect(origin: .zero, size: documentSize)
        }

        let imageOrigin = NSPoint(
            x: (documentSize.width - imageFrameSize.width) / 2,
            y: (documentSize.height - imageFrameSize.height) / 2
        )
        let imageFrame = NSRect(origin: imageOrigin, size: imageFrameSize)

        if imageView.frame != imageFrame {
            imageView.frame = imageFrame
        }

        imageView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        imageView.layer?.position = CGPoint(x: imageFrame.midX, y: imageFrame.midY)
        imageView.layer?.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(rotationQuarterTurns) * (.pi / 2)))

        if shouldCenterOnNextLayout {
            photoCenter = CGPoint(x: 0.5, y: 0.5)
            shouldCenterOnNextLayout = false
        }
        if shouldReposition {
            scrollToPhotoPoint(photoCenter)
        }
        updateMinimap()
    }

    private func scrollToPhotoPoint(_ point: CGPoint) {
        guard let geometry else { return }
        photoCenter = point
        contentView.scroll(to: geometry.scrollOrigin(centering: point))
        reflectScrolledClipView(contentView)
        // Autohiding legacy scrollers can change the viewport again while reflecting.
        guard contentView.bounds.size == geometry.viewportSize else {
            needsLayout = true
            return
        }
        photoCenter = geometry.photoPoint(at: contentView.bounds.center)
        updateMinimap()
    }

    @objc private func clipBoundsDidChange(_ notification: Notification) {
        guard !isLayingOut, let geometry else { return }
        // Resizing can constrain the old clip origin before layout has updated the photo.
        // Keep the last scroll position until the new geometry is ready.
        guard contentView.bounds.size == geometry.viewportSize else {
            needsLayout = true
            return
        }
        photoCenter = geometry.photoPoint(at: contentView.bounds.center)
        updateMinimap()
    }

    private func updateMinimap() {
        guard let geometry, contentView.bounds.size == geometry.viewportSize else { return }
        let viewport = contentView.bounds
        minimapView.isHidden = viewport.contains(geometry.photoRect)
        guard !minimapView.isHidden else { return }

        let viewportFrame = convert(contentView.bounds, from: contentView)
        let inset: CGFloat = 12
        let availableWidth = max(0, viewportFrame.width - inset * 2)
        let availableHeight = max(0, viewportFrame.height - inset * 2)
        let longestSide = min(160, availableWidth, availableHeight)
        let size = geometry.photoRect.size
        let scale = longestSide / max(size.width, size.height)
        let minimapSize = CGSize(width: size.width * scale, height: size.height * scale)
        minimapView.frame = CGRect(
            x: viewportFrame.maxX - inset - minimapSize.width,
            y: isFlipped ? viewportFrame.minY + inset : viewportFrame.maxY - inset - minimapSize.height,
            width: minimapSize.width,
            height: minimapSize.height
        )
        minimapView.image = currentImage
        minimapView.rotationQuarterTurns = rotationQuarterTurns
        minimapView.visiblePhotoRect = geometry.minimapVisibleRect(
            viewportBounds: viewport,
            minimapBounds: minimapView.bounds
        )
        minimapView.needsDisplay = true
    }
}

/// Geometry uses the displayed, rotated photo and AppKit's upward-growing y axis.
struct ZoomGeometry: Equatable {
    let viewportSize: CGSize
    let documentSize: CGSize
    let photoRect: CGRect

    init(imageSize: CGSize, viewportSize: CGSize, rotationQuarterTurns: Int) {
        self.viewportSize = viewportSize
        let fittedSize = fittedDisplaySize(
            for: imageSize, in: viewportSize, rotationQuarterTurns: rotationQuarterTurns
        )
        let displayedSize = CGSize(width: fittedSize.width * 2, height: fittedSize.height * 2)
        documentSize = CGSize(
            width: max(displayedSize.width, viewportSize.width),
            height: max(displayedSize.height, viewportSize.height)
        )
        photoRect = CGRect(
            x: (documentSize.width - displayedSize.width) / 2,
            y: (documentSize.height - displayedSize.height) / 2,
            width: displayedSize.width,
            height: displayedSize.height
        )
    }

    func photoPoint(at documentPoint: CGPoint) -> CGPoint {
        Self.unitPoint(at: documentPoint, in: photoRect)
    }

    func scrollOrigin(centering point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(0, photoRect.minX + point.x * photoRect.width - viewportSize.width / 2),
                   documentSize.width - viewportSize.width),
            y: min(max(0, photoRect.minY + point.y * photoRect.height - viewportSize.height / 2),
                   documentSize.height - viewportSize.height)
        )
    }

    func minimapVisibleRect(viewportBounds: CGRect, minimapBounds: CGRect) -> CGRect {
        let visible = photoRect.intersection(viewportBounds)
        guard !visible.isNull else { return .zero }
        return CGRect(
            x: minimapBounds.minX + (visible.minX - photoRect.minX) / photoRect.width * minimapBounds.width,
            y: minimapBounds.minY + (visible.minY - photoRect.minY) / photoRect.height * minimapBounds.height,
            width: visible.width / photoRect.width * minimapBounds.width,
            height: visible.height / photoRect.height * minimapBounds.height
        )
    }

    static func unitPoint(at point: CGPoint, in rect: CGRect) -> CGPoint {
        guard rect.width > 0, rect.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(
            x: min(1, max(0, (point.x - rect.minX) / rect.width)),
            y: min(1, max(0, (point.y - rect.minY) / rect.height))
        )
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

private final class ZoomMinimapView: NSView {
    var image: NSImage? {
        didSet {
            guard image !== oldValue else { return }
            cachedBitmap = image.flatMap { Self.makeBitmap(for: $0) }
            needsDisplay = true
        }
    }
    private var cachedBitmap: NSBitmapImageRep?
    var rotationQuarterTurns = 0
    var visiblePhotoRect = CGRect.zero
    var panToPoint: ((CGPoint) -> Void)?

    override var acceptsFirstResponder: Bool { false }

    private static func makeBitmap(for image: NSImage) -> NSBitmapImageRep? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        // A 320 px bitmap covers the minimap's maximum 160 pt size on Retina.
        let scale = 320 / max(size.width, size.height)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int((size.width * scale).rounded())),
            pixelsHigh: max(1, Int((size.height * scale).rounded())),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        return bitmap
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let cachedBitmap, bounds.width > 0, bounds.height > 0 else { return }

        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        NSColor(FavrenColors.brand.graphite).withAlphaComponent(0.75).setFill()
        bounds.fill()

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: bounds.midX, yBy: bounds.midY)
        transform.rotate(byDegrees: CGFloat(rotationQuarterTurns) * 90)
        transform.concat()
        let size = imageFrameSize(for: bounds.size, rotationQuarterTurns: rotationQuarterTurns)
        cachedBitmap.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()

        NSColor(FavrenColors.brand.graphite).withAlphaComponent(0.2).setFill()
        let shade = NSBezierPath(rect: bounds)
        shade.appendRect(visiblePhotoRect)
        shade.windingRule = .evenOdd
        shade.fill()
        NSColor.white.setStroke()
        let visible = NSBezierPath(rect: visiblePhotoRect.insetBy(dx: 1, dy: 1))
        visible.lineWidth = 2
        visible.stroke()
        NSGraphicsContext.restoreGraphicsState()

        NSColor(FavrenColors.outline).withAlphaComponent(0.8).setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        pan(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        pan(with: event)
    }

    private func pan(with event: NSEvent) {
        panToPoint?(ZoomGeometry.unitPoint(at: convert(event.locationInWindow, from: nil), in: bounds))
    }
}

private func fittedDisplaySize(
    for imageSize: NSSize,
    in viewportSize: CGSize,
    rotationQuarterTurns: Int
) -> NSSize {
    let displayImageSize = rotatedDisplayImageSize(
        for: imageSize,
        rotationQuarterTurns: rotationQuarterTurns
    )

    let scale = min(
        viewportSize.width / displayImageSize.width,
        viewportSize.height / displayImageSize.height
    )

    return NSSize(
        width: displayImageSize.width * scale,
        height: displayImageSize.height * scale
    )
}

private func imageFrameSize(
    for displaySize: NSSize,
    rotationQuarterTurns: Int
) -> NSSize {
    if ((rotationQuarterTurns % 4) + 4) % 4 % 2 == 1 {
        return NSSize(width: displaySize.height, height: displaySize.width)
    }

    return displaySize
}

private func rotatedDisplayImageSize(
    for imageSize: NSSize,
    rotationQuarterTurns: Int
) -> NSSize {
    if ((rotationQuarterTurns % 4) + 4) % 4 % 2 == 1 {
        return NSSize(width: imageSize.height, height: imageSize.width)
    }

    return imageSize
}
