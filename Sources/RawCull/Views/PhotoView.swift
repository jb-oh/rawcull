import AppKit
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
                flashColor = newValue == .pick ? .green : .red
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
    private var currentImage: NSImage?
    private var rotationQuarterTurns = 0
    private var shouldCenterOnNextLayout = true
    private let zoomScale: CGFloat = 2.0

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
        super.layout()

        guard let image = currentImage else { return }

        let viewportSize = contentView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let fittedSize = fittedDisplaySize(
            for: imageSize,
            in: viewportSize,
            rotationQuarterTurns: rotationQuarterTurns
        )
        let documentSize = NSSize(
            width: fittedSize.width * zoomScale,
            height: fittedSize.height * zoomScale
        )
        let imageFrameSize = imageFrameSize(
            for: documentSize,
            rotationQuarterTurns: rotationQuarterTurns
        )

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
            centerOnImageMidpoint()
            shouldCenterOnNextLayout = false
        }
    }

    private func centerOnImageMidpoint() {
        let documentSize = containerView.frame.size
        let viewportSize = contentView.bounds.size

        let origin = NSPoint(
            x: max(0, (documentSize.width - viewportSize.width) / 2),
            y: max(0, (documentSize.height - viewportSize.height) / 2)
        )

        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
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
