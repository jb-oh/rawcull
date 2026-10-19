import Foundation
import Testing
@testable import RawCull

struct ZoomGeometryTests {
    @Test func narrowTallViewportCentersPhotoWithoutVerticalScrolling() {
        let geometry = ZoomGeometry(
            imageSize: CGSize(width: 4000, height: 2000),
            viewportSize: CGSize(width: 300, height: 1000),
            rotationQuarterTurns: 0
        )

        #expect(geometry.documentSize == CGSize(width: 600, height: 1000))
        #expect(geometry.photoRect == CGRect(x: 0, y: 350, width: 600, height: 300))
        #expect(geometry.scrollOrigin(centering: CGPoint(x: 0.5, y: 0.5)) == CGPoint(x: 150, y: 0))
        #expect(geometry.scrollOrigin(centering: .zero) == .zero)
        #expect(geometry.scrollOrigin(centering: CGPoint(x: 1, y: 1)) == CGPoint(x: 300, y: 0))
    }

    @Test func shortWideViewportCentersPortraitWithoutHorizontalScrolling() {
        let geometry = ZoomGeometry(
            imageSize: CGSize(width: 2000, height: 4000),
            viewportSize: CGSize(width: 1000, height: 300),
            rotationQuarterTurns: 0
        )

        #expect(geometry.documentSize == CGSize(width: 1000, height: 600))
        #expect(geometry.photoRect == CGRect(x: 350, y: 0, width: 300, height: 600))
        #expect(geometry.scrollOrigin(centering: CGPoint(x: 0.5, y: 0.5)) == CGPoint(x: 0, y: 150))
        #expect(geometry.scrollOrigin(centering: .zero) == .zero)
        #expect(geometry.scrollOrigin(centering: CGPoint(x: 1, y: 1)) == CGPoint(x: 0, y: 300))
    }

    @Test func wideViewportScrollsToBothPhotoEdgesOnBothAxes() {
        let geometry = ZoomGeometry(
            imageSize: CGSize(width: 4000, height: 3000),
            viewportSize: CGSize(width: 1600, height: 900),
            rotationQuarterTurns: 0
        )

        #expect(geometry.documentSize == CGSize(width: 2400, height: 1800))
        #expect(geometry.photoRect.origin == .zero)
        #expect(geometry.scrollOrigin(centering: CGPoint(x: 0.5, y: 0.5)) == CGPoint(x: 400, y: 450))
        #expect(geometry.scrollOrigin(centering: .zero) == .zero)
        #expect(geometry.scrollOrigin(centering: CGPoint(x: 1, y: 1)) == CGPoint(x: 800, y: 900))
    }

    @Test(arguments: [-3, -1, 1, 3, 5])
    func quarterTurnsUseDisplayedPhotoDimensions(turns: Int) {
        let geometry = ZoomGeometry(
            imageSize: CGSize(width: 4000, height: 2000),
            viewportSize: CGSize(width: 300, height: 1000),
            rotationQuarterTurns: turns
        )

        #expect(geometry.documentSize == CGSize(width: 600, height: 1200))
        #expect(geometry.photoRect == CGRect(x: 0, y: 0, width: 600, height: 1200))
        #expect(geometry.scrollOrigin(centering: CGPoint(x: 0.5, y: 0.5)) == CGPoint(x: 150, y: 100))
    }

    @Test func detailResolutionAndSavedRotationHaveTheSameDisplayedGeometry() {
        let viewport = CGSize(width: 300, height: 1000)
        let preview = ZoomGeometry(
            imageSize: CGSize(width: 4000, height: 2000), viewportSize: viewport, rotationQuarterTurns: 1
        )
        let detail = ZoomGeometry(
            imageSize: CGSize(width: 8000, height: 4000), viewportSize: viewport, rotationQuarterTurns: 1
        )
        let savedRotation = ZoomGeometry(
            imageSize: CGSize(width: 2000, height: 4000), viewportSize: viewport, rotationQuarterTurns: 0
        )

        #expect(preview == detail)
        #expect(preview == savedRotation)
    }

    @Test func resizePreservesTheSamePhotoPointAndClampsWhenAnAxisStopsScrolling() {
        let imageSize = CGSize(width: 4000, height: 3000)
        let before = ZoomGeometry(
            imageSize: imageSize, viewportSize: CGSize(width: 800, height: 600), rotationQuarterTurns: 0
        )
        let photoPoint = before.photoPoint(at: CGPoint(x: 1040, y: 720))
        #expect(photoPoint == CGPoint(x: 0.65, y: 0.6))

        let after = ZoomGeometry(
            imageSize: imageSize, viewportSize: CGSize(width: 700, height: 800), rotationQuarterTurns: 0
        )
        let origin = after.scrollOrigin(centering: photoPoint)
        #expect(origin == CGPoint(x: 560, y: 230))
        #expect(after.photoPoint(at: CGPoint(x: origin.x + 350, y: origin.y + 400)) == photoPoint)

        let tall = ZoomGeometry(
            imageSize: imageSize, viewportSize: CGSize(width: 700, height: 1200), rotationQuarterTurns: 0
        )
        #expect(tall.scrollOrigin(centering: photoPoint) == CGPoint(x: 560, y: 0))
        #expect(tall.photoPoint(at: CGPoint(x: 910, y: 600)) == CGPoint(x: 0.65, y: 0.5))
    }

    @Test func minimapClampsVisibleRegionToPhotoAndIncludesItsDocumentOffset() {
        let geometry = ZoomGeometry(
            imageSize: CGSize(width: 4000, height: 2000),
            viewportSize: CGSize(width: 300, height: 1000),
            rotationQuarterTurns: 0
        )
        let minimap = CGRect(x: 10, y: 20, width: 160, height: 80)

        #expect(geometry.minimapVisibleRect(
            viewportBounds: CGRect(x: 150, y: 0, width: 300, height: 1000), minimapBounds: minimap
        ) == CGRect(x: 50, y: 20, width: 80, height: 80))
        #expect(geometry.minimapVisibleRect(
            viewportBounds: CGRect(x: 300, y: 0, width: 300, height: 1000), minimapBounds: minimap
        ) == CGRect(x: 90, y: 20, width: 80, height: 80))
        #expect(geometry.minimapVisibleRect(
            viewportBounds: CGRect(x: -100, y: -100, width: 1000, height: 2000), minimapBounds: minimap
        ) == minimap)
    }

    @Test func minimapTopMapsToPhotoTopWithNonFlippedCoordinates() {
        let geometry = ZoomGeometry(
            imageSize: CGSize(width: 4000, height: 3000),
            viewportSize: CGSize(width: 1600, height: 900),
            rotationQuarterTurns: 0
        )
        let minimap = CGRect(x: 0, y: 0, width: 160, height: 120)
        let bottom = geometry.minimapVisibleRect(
            viewportBounds: CGRect(origin: .zero, size: geometry.viewportSize), minimapBounds: minimap
        )
        let top = geometry.minimapVisibleRect(
            viewportBounds: CGRect(x: 800, y: 900, width: 1600, height: 900), minimapBounds: minimap
        )

        #expect(bottom.minY == minimap.minY)
        #expect(bottom.height == 60)
        #expect(top.minY == 60)
        #expect(top.maxY == minimap.maxY)
        #expect(top.maxX == minimap.maxX)
        let topRightPoint = ZoomGeometry.unitPoint(at: CGPoint(x: 160, y: 120), in: minimap)
        #expect(topRightPoint == CGPoint(x: 1, y: 1))
        #expect(geometry.scrollOrigin(centering: topRightPoint) == CGPoint(x: 800, y: 900))
        #expect(ZoomGeometry.unitPoint(at: CGPoint(x: -20, y: 200), in: minimap) == CGPoint(x: 0, y: 1))
    }
}
