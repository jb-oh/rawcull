import Foundation
import AppKit
import ImageIO
import Observation

@MainActor
@Observable
final class ImageLoader {
    // Thumbnail cache: load lazily and keep only a bounded working set.
    private var thumbnailCache: [URL: NSImage] = [:]
    @ObservationIgnored
    private var thumbnailAccessOrder: [URL] = []
    // A 3:2 photo at 480 x 320 x 4 bytes is about 0.6 MB, so 160 images stay near 94 MB
    // (141 MB for square images) while scrolling back stays cheap.
    private let maxThumbnailCacheCount = 160
    private let thumbnailMaxPixelSize = 480

    // Preview cache: larger images for the main fitted view, LRU limited.
    private var previewCache: [URL: NSImage] = [:]
    @ObservationIgnored
    private var previewAccessOrder: [URL] = []
    private let maxPreviewCacheCount = 12
    private let previewMaxPixelSize = 4096

    // Detail cache: very high-resolution image for the current zoomed photo.
    private var detailCache: [URL: NSImage] = [:]
    @ObservationIgnored
    private var detailAccessOrder: [URL] = []
    private let maxDetailCacheCount = 2
    private let detailMaxPixelSize = 8192

    @ObservationIgnored
    private var thumbnailTasks: [URL: Task<Void, Never>] = [:]
    @ObservationIgnored
    private var prefetchTasks: [Task<Void, Never>] = []
    @ObservationIgnored
    private var detailTasks: [URL: Task<Void, Never>] = [:]

    @ObservationIgnored
    private var allItems: [PhotoItem] = []
    @ObservationIgnored
    private var pinnedPreviewURL: URL?

    private struct LoadRevision: Equatable {
        let generation: Int
        let revision: Int
    }

    private enum ImageSize: Hashable {
        case thumbnail, preview, detail
    }

    @ObservationIgnored
    private var generation = 0
    @ObservationIgnored
    private var revisions: [URL: Int] = [:]
    @ObservationIgnored
    private var rotationLoads: [URL: Set<ImageSize>] = [:]
    @ObservationIgnored
    private let decodeImage: @Sendable (URL, Int) -> NSImage?

    init(decodeImage: @escaping @Sendable (URL, Int) -> NSImage? = ImageLoader.loadImage) {
        self.decodeImage = decodeImage
    }

    // MARK: - Public API

    func startLoading(items: [PhotoItem], currentIndex: Int) {
        allItems = items
        prefetch(around: currentIndex)
    }

    func thumbnail(for url: URL) -> NSImage? {
        thumbnailCache[url]
    }

    func preview(for url: URL) -> NSImage? {
        previewCache[url]
    }

    func detail(for url: URL) -> NSImage? {
        detailCache[url]
    }

    func loadThumbnailIfNeeded(for url: URL) {
        if rotationLoads[url] != nil {
            rotationLoads[url]?.insert(.thumbnail)
            return
        }
        guard thumbnailCache[url] == nil, thumbnailTasks[url] == nil else { return }
        let revision = loadRevision(for: url)
        let decode = decodeImage
        let maxSize = thumbnailMaxPixelSize

        let task = Task.detached(priority: .utility) { [weak self] in
            let image = decode(url, maxSize)
            await MainActor.run {
                guard let self, self.loadRevision(for: url) == revision else { return }
                self.thumbnailTasks.removeValue(forKey: url)
                guard let image else { return }
                self.cacheThumbnail(image, for: url)
            }
        }

        thumbnailTasks[url] = task
    }

    func loadPreviewIfNeeded(for url: URL, priority: TaskPriority) {
        if rotationLoads[url] != nil {
            rotationLoads[url]?.insert(.preview)
            return
        }
        guard previewCache[url] == nil else { return }
        let revision = loadRevision(for: url)
        let decode = decodeImage
        let maxSize = previewMaxPixelSize

        let task = Task.detached(priority: priority) { [weak self] in
            guard !Task.isCancelled else { return }
            let image = decode(url, maxSize)

            await MainActor.run {
                guard let self, self.loadRevision(for: url) == revision, let image else { return }
                self.cachePreview(image, for: url)
            }
        }

        prefetchTasks.append(task)
    }

    func prefetch(around index: Int) {
        guard !allItems.isEmpty else { return }
        let currentURL = allItems[index].url
        pinnedPreviewURL = currentURL

        prefetchThumbnails(around: index)

        for task in prefetchTasks {
            task.cancel()
        }
        prefetchTasks.removeAll()

        let range = max(0, index - 5)...min(allItems.count - 1, index + 5)
        loadPreviewIfNeeded(for: currentURL, priority: .userInitiated)

        for i in range {
            let url = allItems[i].url
            guard url != currentURL else { continue }
            loadPreviewIfNeeded(for: url, priority: .utility)
        }
    }

    func loadDetailIfNeeded(for url: URL) {
        if rotationLoads[url] != nil {
            rotationLoads[url]?.insert(.detail)
            return
        }
        guard detailCache[url] == nil, detailTasks[url] == nil else { return }
        let revision = loadRevision(for: url)
        let decode = decodeImage
        let maxSize = detailMaxPixelSize

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let image = decode(url, maxSize)

            await MainActor.run {
                guard let self, self.loadRevision(for: url) == revision else { return }
                self.detailTasks.removeValue(forKey: url)
                guard let image else { return }
                self.cacheDetail(image, for: url)
            }
        }

        detailTasks[url] = task
    }

    /// Keep cached pixels visible while discarding decodes that could race the file write.
    @discardableResult
    func beginRotationWrite(for url: URL) -> Bool {
        guard rotationLoads[url] == nil else { return false }
        var requested: Set<ImageSize> = [.thumbnail, .preview]
        if detailTasks[url] != nil { requested.insert(.detail) }
        rotationLoads[url] = requested
        revisions[url, default: 0] += 1
        thumbnailTasks.removeValue(forKey: url)?.cancel()
        detailTasks.removeValue(forKey: url)?.cancel()
        return true
    }

    /// Called on the main actor with the view rotation reset in the same update.
    func applySavedRotation(quarterTurns: Int, for url: URL) {
        revisions[url, default: 0] += 1
        if let image = thumbnailCache[url] {
            thumbnailCache[url] = Self.rotatedImage(image, quarterTurns: quarterTurns)
        }
        if let image = previewCache[url] {
            previewCache[url] = Self.rotatedImage(image, quarterTurns: quarterTurns)
        }
        if let image = detailCache[url] {
            detailCache[url] = Self.rotatedImage(image, quarterTurns: quarterTurns)
        }
        resumeRotationLoads(for: url)
    }

    func cancelRotationWrite(for url: URL) {
        resumeRotationLoads(for: url)
    }

    private func loadRevision(for url: URL) -> LoadRevision {
        LoadRevision(generation: generation, revision: revisions[url, default: 0])
    }

    private func resumeRotationLoads(for url: URL) {
        guard let requested = rotationLoads.removeValue(forKey: url) else { return }
        if requested.contains(.thumbnail) { loadThumbnailIfNeeded(for: url) }
        if requested.contains(.preview) { loadPreviewIfNeeded(for: url, priority: .userInitiated) }
        if requested.contains(.detail) { loadDetailIfNeeded(for: url) }
    }

    func clearAll() {
        generation += 1
        // Writes outlive folder switches. Keep their per-URL load barriers until completion.
        for task in prefetchTasks { task.cancel() }
        for (_, task) in thumbnailTasks { task.cancel() }
        for (_, task) in detailTasks { task.cancel() }
        prefetchTasks.removeAll()
        thumbnailTasks.removeAll()
        detailTasks.removeAll()
        thumbnailCache.removeAll()
        thumbnailAccessOrder.removeAll()
        previewCache.removeAll()
        previewAccessOrder.removeAll()
        detailCache.removeAll()
        detailAccessOrder.removeAll()
        pinnedPreviewURL = nil
        allItems.removeAll()
    }

    // MARK: - Private Loading

    private func prefetchThumbnails(around index: Int) {
        let range = max(0, index - 20)...min(allItems.count - 1, index + 20)
        for i in range {
            loadThumbnailIfNeeded(for: allItems[i].url)
        }
    }

    private func cacheThumbnail(_ image: NSImage, for url: URL) {
        thumbnailCache[url] = image
        touchThumbnail(url)

        while thumbnailCache.count > maxThumbnailCacheCount {
            guard let oldest = thumbnailAccessOrder.first else { break }
            thumbnailAccessOrder.removeFirst()
            thumbnailCache.removeValue(forKey: oldest)
        }
    }

    private func cachePreview(_ image: NSImage, for url: URL) {
        previewCache[url] = image
        touchPreview(url)

        while previewCache.count > maxPreviewCacheCount {
            guard let oldest = previewAccessOrder.first else { break }
            previewAccessOrder.removeFirst()

             if oldest == pinnedPreviewURL {
                previewAccessOrder.append(oldest)
                continue
            }

            previewCache.removeValue(forKey: oldest)
        }
    }

    private func cacheDetail(_ image: NSImage, for url: URL) {
        detailCache[url] = image
        touchDetail(url)

        while detailCache.count > maxDetailCacheCount {
            guard let oldest = detailAccessOrder.first else { break }
            detailAccessOrder.removeFirst()
            detailCache.removeValue(forKey: oldest)
        }
    }

    private func touchThumbnail(_ url: URL) {
        if let idx = thumbnailAccessOrder.firstIndex(of: url) {
            thumbnailAccessOrder.remove(at: idx)
        }
        thumbnailAccessOrder.append(url)
    }

    private func touchPreview(_ url: URL) {
        if let idx = previewAccessOrder.firstIndex(of: url) {
            previewAccessOrder.remove(at: idx)
        }
        previewAccessOrder.append(url)
    }

    private func touchDetail(_ url: URL) {
        if let idx = detailAccessOrder.firstIndex(of: url) {
            detailAccessOrder.remove(at: idx)
        }
        detailAccessOrder.append(url)
    }

    // MARK: - Image Decoding

    nonisolated static func loadImage(from url: URL, maxSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let displayImage: CGImage
        if RotationWriter.isRAW(url), let orientation = RotationWriter.sidecarOrientation(for: url) {
            let turns = RotationWriter.delta(from: RotationWriter.embeddedOrientation(in: source), to: orientation)
            guard let rotated = rotate(cgImage, quarterTurns: turns) else { return nil }
            displayImage = rotated
        } else {
            displayImage = cgImage
        }
        return NSImage(cgImage: displayImage, size: NSSize(width: displayImage.width, height: displayImage.height))
    }

    private static func rotatedImage(_ image: NSImage, quarterTurns: Int) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let rotated = rotate(cgImage, quarterTurns: quarterTurns) else { return nil }
        return NSImage(cgImage: rotated, size: NSSize(width: rotated.width, height: rotated.height))
    }

    nonisolated static func rotate(_ image: CGImage, quarterTurns: Int) -> CGImage? {
        let turns = RotationWriter.normalizedTurns(quarterTurns)
        guard turns != 0 else { return image }
        let width = turns % 2 == 0 ? image.width : image.height
        let height = turns % 2 == 0 ? image.height : image.width
        let colorSpace: CGColorSpace
        if let sourceSpace = image.colorSpace, sourceSpace.model == .rgb {
            colorSpace = sourceSpace
        } else {
            colorSpace = CGColorSpaceCreateDeviceRGB()
        }
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: -CGFloat(turns) * .pi / 2)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(
            x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
            width: CGFloat(image.width), height: CGFloat(image.height)
        ))
        return context.makeImage()
    }
}
