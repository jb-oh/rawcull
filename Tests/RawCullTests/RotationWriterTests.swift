import AppKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import RawCull

enum RotationFixture {
    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func image() throws -> CGImage {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 12, height: 8, bitsPerComponent: 8, bytesPerRow: 48,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(try #require(CGColor(colorSpace: colorSpace, components: [1, 0, 0, 1])))
        context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        context.setFillColor(try #require(CGColor(colorSpace: colorSpace, components: [0, 1, 0, 1])))
        context.fill(CGRect(x: 0, y: 4, width: 6, height: 4))
        return try #require(context.makeImage())
    }

    static func jpeg(at url: URL, orientation: Int = 1) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFOrientation: orientation,
                kCGImagePropertyTIFFArtist: "Rotation test"
            ]
        ]
        CGImageDestinationAddImage(destination, try image(), properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
    }

    static func properties(at url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    static func pixels(at url: URL) throws -> Data {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try #require(image.dataProvider?.data) as Data
    }

    static func writeXMP(at url: URL, orientation: Int = 8) throws {
        let xmp = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about="" xmlns:tiff="http://ns.adobe.com/tiff/1.0/"
                xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:custom="https://rawcull.test/metadata/"
                tiff:Orientation="\(orientation)" xmp:Rating="3" custom:Note="Keep me"/>
          </rdf:RDF>
        </x:xmpmeta>
        """
        try Data(xmp.utf8).write(to: url)
    }
}

struct RotationWriterTests {
    @Test(arguments: 1...8, [-1, 1, 2, 3, 5])
    func compositionAndDeltaRoundTrip(orientation: Int, turns: Int) {
        let expectedCycles = [[1, 6, 3, 8], [2, 7, 4, 5]]
        let cycle = expectedCycles.first { $0.contains(orientation) }!
        let index = cycle.firstIndex(of: orientation)!
        let normalized = ((turns % 4) + 4) % 4
        let expected = cycle[(index + normalized) % 4]
        #expect(RotationWriter.compose(orientation: orientation, quarterTurns: turns) == expected)
        #expect(RotationWriter.delta(from: orientation, to: expected) == normalized)
        #expect(RotationWriter.compose(orientation: expected, quarterTurns: -turns) == orientation)
    }

    @Test(arguments: [-1, 0, 9, Int.max])
    func invalidOrientationCountsAsUpright(orientation: Int) {
        #expect(RotationWriter.compose(orientation: orientation, quarterTurns: 1) == 6)
        #expect(RotationWriter.delta(from: orientation, to: 6) == 1)
        #expect(RotationWriter.delta(from: 6, to: orientation) == 3)
    }

    @Test func extremeTurnCountsAndMirrorIndependentDelta() {
        #expect(RotationWriter.compose(orientation: 1, quarterTurns: Int.min) == 1)
        #expect(RotationWriter.compose(orientation: 1, quarterTurns: Int.max) == 8)
        #expect(RotationWriter.delta(from: 2, to: 6) == 1)
        #expect(RotationWriter.delta(from: 7, to: 3) == 1)
    }

    @MainActor
    @Test func batchWritesEveryJPEGAndUpdatesCachedThumbnails() async throws {
        let directory = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = (0..<3).map { directory.appendingPathComponent("\($0).jpg") }
        for url in urls { try RotationFixture.jpeg(at: url) }
        let loader = ImageLoader()
        defer { loader.clearAll() }
        for url in urls { loader.loadThumbnailIfNeeded(for: url) }
        for _ in 0..<100 {
            if urls.allSatisfy({ loader.thumbnail(for: $0) != nil }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(urls.allSatisfy { loader.thumbnail(for: $0)?.size == NSSize(width: 12, height: 8) })
        var saved: [URL] = []
        let result = await RotationWriter.applyBatch(quarterTurns: 1, to: urls, imageLoader: loader) {
            saved.append($0)
            #expect(loader.thumbnail(for: $0)?.size == NSSize(width: 8, height: 12))
        }
        #expect(result.savedURLs == urls)
        #expect(result.failedCount == 0)
        #expect(result.firstError == nil)
        #expect(saved == urls)
        for url in urls {
            #expect((try RotationFixture.properties(at: url)[kCGImagePropertyOrientation] as? NSNumber)?.intValue == 6)
            #expect(loader.beginRotationWrite(for: url))
            loader.cancelRotationWrite(for: url)
        }
    }

    @MainActor
    @Test func batchContinuesAfterMiddleFailureAndCountsBusyFilesWithoutUnlockingThem() async throws {
        let directory = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = (0..<4).map { directory.appendingPathComponent("\($0).jpg") }
        for url in urls { try RotationFixture.jpeg(at: url) }
        let broken = Data("not a JPEG".utf8)
        try broken.write(to: urls[1])
        let busyBytes = try Data(contentsOf: urls[2])
        let loader = ImageLoader()
        defer { loader.clearAll() }
        #expect(loader.beginRotationWrite(for: urls[2]))
        var saved: [URL] = []
        let result = await RotationWriter.applyBatch(quarterTurns: -1, to: urls, imageLoader: loader) { saved.append($0) }
        #expect(result.savedURLs == [urls[0], urls[3]])
        #expect(result.failedURLs == [urls[1], urls[2]])
        #expect(result.savedCount == 2 && result.failedCount == 2)
        #expect(result.firstError != nil)
        #expect(saved == result.savedURLs)
        for url in result.savedURLs {
            #expect((try RotationFixture.properties(at: url)[kCGImagePropertyOrientation] as? NSNumber)?.intValue == 8)
        }
        #expect(try Data(contentsOf: urls[1]) == broken)
        #expect(try Data(contentsOf: urls[2]) == busyBytes)
        #expect(!loader.beginRotationWrite(for: urls[2]))
        loader.cancelRotationWrite(for: urls[2])
        #expect(loader.beginRotationWrite(for: urls[1]))
        loader.cancelRotationWrite(for: urls[1])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == urls.map(\.lastPathComponent))
    }

    @Test func previewKeepsNewTurnsAndDoesNotDoubleRotateCompletedFiles() throws {
        let first = URL(fileURLWithPath: "/tmp/first.jpg")
        let second = URL(fileURLWithPath: "/tmp/second.jpg")
        var preview = RotationPreview()
        preview.rotate(by: 1)
        let pending = preview.beginSave()
        let write = try #require(pending)
        #expect(preview.beginSave() == nil)
        preview.didSave(first, write: write)
        #expect(preview.turns(for: first) == 0)
        #expect(preview.turns(for: second) == 1)
        preview.rotate(by: 1)
        #expect(preview.turns(for: first) == 1)
        #expect(preview.turns(for: second) == 2)
        preview.finish(write, savedCount: 1)
        #expect(preview.quarterTurns == 1)
        #expect(preview.turns(for: first) == 1)
        #expect(preview.turns(for: second) == 1)
    }

    @Test func resetRejectsOldWriteCallbacksAndFailedSaveKeepsPendingTurns() throws {
        let url = URL(fileURLWithPath: "/tmp/reset.jpg")
        var preview = RotationPreview()
        preview.rotate(by: -1)
        let oldPending = preview.beginSave()
        let oldWrite = try #require(oldPending)
        preview.reset()
        preview.rotate(by: 1)
        let newPending = preview.beginSave()
        let newWrite = try #require(newPending)
        preview.didSave(url, write: oldWrite)
        preview.finish(oldWrite, savedCount: 1)
        #expect(preview.turns(for: url) == 1)
        preview.finish(newWrite, savedCount: 0)
        #expect(preview.quarterTurns == 1)
        #expect(preview.beginSave() != nil)
        preview.reset()
        #expect(preview.turns(for: url) == 0)
        #expect(preview.beginSave() == nil)
    }

    @Test func jpegUpdatesOnlyMetadataAndLeavesNoTemporaryFiles() throws {
        let directory = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("photo.jpg")
        try RotationFixture.jpeg(at: url)
        let pixels = try RotationFixture.pixels(at: url)

        for expected in [6, 3] {
            try RotationWriter.apply(quarterTurns: 1, to: url)
            let properties = try RotationFixture.properties(at: url)
            #expect((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue == expected)
            #expect((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 12)
            #expect((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == 8)
            let tiff = try #require(properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
            #expect((tiff[kCGImagePropertyTIFFOrientation] as? NSNumber)?.intValue == expected)
            #expect(tiff[kCGImagePropertyTIFFArtist] as? String == "Rotation test")
            #expect(try RotationFixture.pixels(at: url) == pixels)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["photo.jpg"])
        }
    }

    @Test func fakeRAWCreatesSidecarWithoutChangingRAWBytes() throws {
        let directory = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = directory.appendingPathComponent("x.cr3")
        let original = Data("fake raw".utf8)
        try original.write(to: raw)

        try RotationWriter.apply(quarterTurns: 1, to: raw)

        #expect(RotationWriter.sidecarOrientation(for: raw) == 6)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("x.xmp").path))
        #expect(try Data(contentsOf: raw) == original)
    }

    @Test func sidecarOrientationReadsUppercaseXMP() throws {
        let directory = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = directory.appendingPathComponent("X.CR3")
        try RotationFixture.writeXMP(at: directory.appendingPathComponent("X.XMP"), orientation: 6)

        #expect(RotationWriter.sidecarOrientation(for: raw) == 6)
    }

    @Test func existingUppercaseSidecarComposesAndPreservesOtherMetadata() throws {
        let directory = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = directory.appendingPathComponent("X.CR3")
        let sidecar = directory.appendingPathComponent("X.XMP")
        try Data().write(to: raw)
        try RotationFixture.writeXMP(at: sidecar)
        #expect(RotationWriter.sidecarURL(for: raw) == sidecar)

        try RotationWriter.apply(quarterTurns: 1, to: raw)

        #expect(RotationWriter.sidecarOrientation(for: raw) == 1)
        let metadata = try #require(CGImageMetadataCreateFromXMPData(try Data(contentsOf: sidecar) as CFData))
        #expect(CGImageMetadataCopyStringValueWithPath(metadata, nil, "xmp:Rating" as CFString) as String? == "3")
        #expect(CGImageMetadataCopyStringValueWithPath(metadata, nil, "custom:Note" as CFString) as String? == "Keep me")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == ["X.CR3", "X.XMP"])
    }

    @Test func sidecarFallsBackToEmbeddedOrientationAndInvalidSidecarIsNotOverwritten() throws {
        let directory = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = directory.appendingPathComponent("x.cr3")
        // A decodable fixture with a RAW extension exercises dispatch and embedded orientation.
        try RotationFixture.jpeg(at: raw, orientation: 6)
        try RotationWriter.apply(quarterTurns: 1, to: raw)
        #expect(RotationWriter.sidecarOrientation(for: raw) == 3)

        let sidecar = RotationWriter.sidecarURL(for: raw)
        let invalid = Data("invalid XMP".utf8)
        try invalid.write(to: sidecar)
        #expect(throws: RotationWriter.WriteError.self) {
            try RotationWriter.apply(quarterTurns: 1, to: raw)
        }
        #expect(try Data(contentsOf: sidecar) == invalid)
    }

    @Test func failedImageWriteLeavesOriginalAndNoTemporaryFile() throws {
        let directory = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("broken.jpg")
        let original = Data("not a JPEG".utf8)
        try original.write(to: url)
        #expect(throws: RotationWriter.WriteError.self) {
            try RotationWriter.apply(quarterTurns: 1, to: url)
        }
        #expect(try Data(contentsOf: url) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["broken.jpg"])
    }
}
