import SwiftUI
import Testing
@testable import RawCull

@MainActor
struct StatusBarTests {
    // Position, four stats, then six hints, including the wider Return hint.
    private let sizes: [CGSize] = [
        CGSize(width: 180, height: 22),
        CGSize(width: 70, height: 16),
        CGSize(width: 72, height: 16),
        CGSize(width: 80, height: 16),
        CGSize(width: 45, height: 16),
        CGSize(width: 70, height: 18),
        CGSize(width: 80, height: 18),
        CGSize(width: 70, height: 18),
        CGSize(width: 110, height: 18),
        CGSize(width: 145, height: 18),
        CGSize(width: 95, height: 18)
    ]

    @Test func unitsKeepTheirIdealSizeAndStayInBoundsAcrossWindowWidths() {
        let layout = StatusBarFlowLayout()
        for barWidth in stride(from: 360, through: 1600, by: 1) {
            let width = CGFloat(barWidth - 32) // StatusBar's horizontal padding.
            let result = layout.arrangement(sizes: sizes, width: width, firstHintIndex: 5)
            #expect(result.frames.count == sizes.count)
            for (frame, size) in zip(result.frames, sizes) {
                #expect(frame.size == size)
                #expect(frame.minX >= 0 && frame.maxX <= width)
                #expect(frame.minY >= 0 && frame.maxY <= result.size.height)
            }
            for pair in zip(result.frames, result.frames.dropFirst()) {
                #expect(!pair.0.intersects(pair.1))
            }
        }
    }

    @Test func statsStayOnFirstRowWhenTheyFitAndHintsWrapFirst() {
        let layout = StatusBarFlowLayout()
        let statsWidth = sizes.prefix(5).reduce(0) { $0 + $1.width } + 4 * layout.spacing
        let result = layout.arrangement(sizes: sizes, width: statsWidth, firstHintIndex: 5)
        #expect(result.frames.prefix(5).allSatisfy { $0.midY == 11 })
        #expect(result.frames[5].minX == 0)
        #expect(result.frames[5].minY == 22 + layout.lineSpacing)
        #expect(result.frames[4].maxX == statsWidth)
    }

    @Test func wideBarKeepsStatsLeadingAndHintsTrailingOnOneLine() {
        let result = StatusBarFlowLayout().arrangement(sizes: sizes, width: 1500, firstHintIndex: 5)
        #expect(result.size.height == 22)
        #expect(result.frames[0].minX == 0)
        #expect(result.frames[1].minX == CGFloat(196))
        #expect(result.frames.allSatisfy { $0.midY == 11 })
        #expect(result.frames.last?.maxX == 1500)
        #expect(result.frames[5].minX > result.frames[4].maxX + 16)
    }

    @Test func wrappedRowsStartAtLeadingEdgeWithConsistentSpacing() {
        let result = StatusBarFlowLayout().arrangement(
            sizes: Array(repeating: CGSize(width: 100, height: 20), count: 5),
            width: 216, firstHintIndex: 2
        )
        #expect(result.frames.map(\.origin) == [
            CGPoint(x: 0, y: 0), CGPoint(x: 116, y: 0),
            CGPoint(x: 0, y: 28), CGPoint(x: 116, y: 28),
            CGPoint(x: 0, y: 56)
        ])
        #expect(result.size.height == 76)
    }

    @Test func unspecifiedAndInfiniteWidthsUseOneIdealSizeRow() {
        let layout = StatusBarFlowLayout()
        let idealWidth = sizes.reduce(0) { $0 + $1.width } + 10 * layout.spacing
        for width: CGFloat? in [nil, .infinity] {
            let result = layout.arrangement(sizes: sizes, width: width, firstHintIndex: 5)
            #expect(result.size == CGSize(width: idealWidth, height: 22))
        }
        let empty = layout.arrangement(sizes: [], width: nil, firstHintIndex: nil)
        #expect(empty.size == .zero)
        #expect(empty.frames.isEmpty)
    }

    @Test func selectionCountWrapsWithTheStatsBeforeHints() {
        var sizesWithSelection = sizes
        sizesWithSelection.insert(CGSize(width: 100, height: 16), at: 5)
        let layout = StatusBarFlowLayout()
        for barWidth in stride(from: 360, through: 1600, by: 10) {
            let width = CGFloat(barWidth - 32)
            let result = layout.arrangement(sizes: sizesWithSelection, width: width, firstHintIndex: 6)
            for (frame, size) in zip(result.frames, sizesWithSelection) {
                #expect(frame.size == size)
                #expect(frame.minX >= 0 && frame.maxX <= width)
                #expect(frame.minY >= 0 && frame.maxY <= result.size.height)
            }
            for pair in zip(result.frames, result.frames.dropFirst()) {
                #expect(!pair.0.intersects(pair.1))
            }
        }
    }
}
