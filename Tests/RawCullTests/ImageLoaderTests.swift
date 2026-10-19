import AppKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import RawCull

@MainActor
struct ImageLoaderTests {
    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(predicate())
    }

    private func pixels(_ image: CGImage) throws -> Data {
        let colorSpace = try #require(image.colorSpace)
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try #require(context.data), count: image.width * image.height * 4)
    }

    @Test func pixelRotationIsClockwiseAndSwapsDimensions() throws {
        let image = try RotationFixture.image()
        let rotated = try #require(ImageLoader.rotate(image, quarterTurns: 1))
        #expect(rotated.width == 8)
        #expect(rotated.height == 12)
        let bytes = try pixels(rotated)
        #expect(Array(bytes[0..<3]) == [255, 0, 0])
        #expect(Array(bytes[(6 * 4)..<(6 * 4 + 3)]) == [0, 255, 0])
        let restored = try #require(ImageLoader.rotate(rotated, quarterTurns: -1))
        #expect(try pixels(restored) == pixels(image))
    }

    @Test(arguments: [480, 4096, 8192])
    func rawDecodeAppliesOnlyTheSidecarDeltaAtEverySize(maxSize: Int) throws {
        let directory = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = directory.appendingPathComponent("x.cr3")
        let jpeg = directory.appendingPathComponent("x.jpg")
        try RotationFixture.jpeg(at: raw, orientation: 6)
        try FileManager.default.copyItem(at: raw, to: jpeg)
        try RotationFixture.writeXMP(at: RotationWriter.sidecarURL(for: raw), orientation: 3)

        let embedded = try #require(ImageLoader.loadImage(from: jpeg, maxSize: maxSize))
        let fromSidecar = try #require(ImageLoader.loadImage(from: raw, maxSize: maxSize))
        #expect(embedded.size == NSSize(width: 8, height: 12))
        #expect(fromSidecar.size == NSSize(width: 12, height: 8))
        let embeddedCG = try #require(embedded.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let sidecarCG = try #require(fromSidecar.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let expected = try #require(ImageLoader.rotate(embeddedCG, quarterTurns: 1))
        #expect(try pixels(sidecarCG) == pixels(expected))
    }

    @Test(arguments: [1, 6])
    func thumbnailDecodeFitsTheWidestRetinaColumn(orientation: Int) async throws {
        let directory = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("large.jpg")
        let context = try #require(CGContext(
            data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 4800,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), [
            kCGImagePropertyOrientation: orientation
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        let loader = ImageLoader()
        defer { loader.clearAll() }
        loader.loadThumbnailIfNeeded(for: url)
        try await waitUntil { loader.thumbnail(for: url) != nil }
        let image = try #require(loader.thumbnail(for: url))
        let decoded = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(decoded.width == (orientation == 1 ? 480 : 320))
        #expect(decoded.height == (orientation == 1 ? 320 : 480))
    }

    @Test func thumbnailCacheEvictsBeyond160ImagesAndReloadsEvictedEntries() async throws {
        let image = try RotationFixture.image()
        let loader = ImageLoader { _, size in
            #expect(size == 480)
            return NSImage(cgImage: image, size: NSSize(width: 12, height: 8))
        }
        defer { loader.clearAll() }
        let directory = try RotationFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = (0..<161).map { directory.appendingPathComponent("\($0).jpg") }
        for url in urls {
            loader.loadThumbnailIfNeeded(for: url)
            try await waitUntil { loader.thumbnail(for: url) != nil }
        }
        #expect(loader.thumbnail(for: urls[0]) == nil)
        #expect(urls.dropFirst().allSatisfy { loader.thumbnail(for: $0) != nil })

        loader.loadThumbnailIfNeeded(for: urls[0])
        try await waitUntil { loader.thumbnail(for: urls[0]) != nil }
        #expect(loader.thumbnail(for: urls[1]) == nil)
        #expect(urls.dropFirst(2).allSatisfy { loader.thumbnail(for: $0) != nil })
    }

    @Test func successfulWriteRotatesAllCachedSizesWithoutDecodingAgain() async throws {
        let image = try RotationFixture.image()
        let loader = ImageLoader { _, _ in NSImage(cgImage: image, size: NSSize(width: 12, height: 8)) }
        let url = URL(fileURLWithPath: "/tmp/cached.jpg")
        loader.loadThumbnailIfNeeded(for: url)
        loader.loadPreviewIfNeeded(for: url, priority: .userInitiated)
        loader.loadDetailIfNeeded(for: url)
        try await waitUntil {
            loader.thumbnail(for: url) != nil && loader.preview(for: url) != nil && loader.detail(for: url) != nil
        }

        #expect(loader.beginRotationWrite(for: url))
        #expect(!loader.beginRotationWrite(for: url))
        loader.applySavedRotation(quarterTurns: 1, for: url)

        for cached in [loader.thumbnail(for: url), loader.preview(for: url), loader.detail(for: url)] {
            #expect(cached?.size == NSSize(width: 8, height: 12))
        }
        // A failure preserves the already displayed rotation.
        #expect(loader.beginRotationWrite(for: url))
        loader.cancelRotationWrite(for: url)
        #expect(loader.preview(for: url)?.size == NSSize(width: 8, height: 12))
        loader.clearAll()
    }

    @Test func loadsStartedBeforeWriteCannotOverwriteFreshCaches() async throws {
        let gate = try DecodeGate(image: RotationFixture.image())
        defer { gate.releaseOldLoads() }
        let loader = ImageLoader { _, size in gate.decode(size: size) }
        let url = URL(fileURLWithPath: "/tmp/in-flight.jpg")
        loader.loadThumbnailIfNeeded(for: url)
        loader.loadPreviewIfNeeded(for: url, priority: .userInitiated)
        loader.loadDetailIfNeeded(for: url)
        try await waitUntil { gate.startedCount == 3 }

        loader.beginRotationWrite(for: url)
        loader.loadThumbnailIfNeeded(for: url)
        loader.loadPreviewIfNeeded(for: url, priority: .userInitiated)
        loader.loadDetailIfNeeded(for: url)
        #expect(gate.startedCount == 3)
        loader.applySavedRotation(quarterTurns: 1, for: url)
        try await waitUntil {
            loader.thumbnail(for: url) != nil && loader.preview(for: url) != nil && loader.detail(for: url) != nil
        }

        gate.releaseOldLoads()
        try await waitUntil { gate.finishedOldCount == 3 }
        // Let the old detached tasks reach their main-actor cache insertion callbacks.
        try await Task.sleep(for: .milliseconds(50))
        for cached in [loader.thumbnail(for: url), loader.preview(for: url), loader.detail(for: url)] {
            #expect(cached?.size == NSSize(width: 8, height: 12))
        }
        loader.clearAll()
    }
}

/// The first decode at each size waits until fresh, post-write images have been cached.
private final class DecodeGate: @unchecked Sendable {
    private let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)
    private let original: CGImage
    private let rotated: CGImage
    private var sizes: Set<Int> = []
    private var finished = 0

    init(image: CGImage) throws {
        original = image
        rotated = try #require(ImageLoader.rotate(image, quarterTurns: 1))
    }

    var startedCount: Int { lock.withLock { sizes.count } }
    var finishedOldCount: Int { lock.withLock { finished } }

    func decode(size: Int) -> NSImage {
        let isOld = lock.withLock { sizes.insert(size).inserted }
        if isOld {
            release.wait()
            lock.withLock { finished += 1 }
        }
        let image = isOld ? original : rotated
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    func releaseOldLoads() {
        for _ in 0..<3 { release.signal() }
    }
}
