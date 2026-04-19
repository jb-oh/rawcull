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
    private let maxThumbnailCacheCount = 300

    // Preview cache: larger images for the main fitted view — LRU limited.
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
        guard thumbnailCache[url] == nil, thumbnailTasks[url] == nil else { return }

        let task = Task.detached(priority: .utility) { [weak self] in
            let image = Self.loadImage(from: url, maxSize: 200)
            await MainActor.run {
                guard let self else { return }
                self.thumbnailTasks.removeValue(forKey: url)
                guard let image else { return }
                self.cacheThumbnail(image, for: url)
            }
        }

        thumbnailTasks[url] = task
    }

    func loadPreviewIfNeeded(for url: URL, priority: TaskPriority) {
        guard previewCache[url] == nil else { return }

        let task = Task.detached(priority: priority) { [weak self] in
            guard !Task.isCancelled else { return }
            let image = Self.loadImage(from: url, maxSize: self?.previewMaxPixelSize ?? 4096)

            await MainActor.run {
                guard let self, let image else { return }
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
        guard detailCache[url] == nil, detailTasks[url] == nil else { return }

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let image = Self.loadImage(from: url, maxSize: self.detailMaxPixelSize)

            await MainActor.run {
                self.detailTasks.removeValue(forKey: url)
                guard let image else { return }
                self.cacheDetail(image, for: url)
            }
        }

        detailTasks[url] = task
    }

    func clearAll() {
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

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
