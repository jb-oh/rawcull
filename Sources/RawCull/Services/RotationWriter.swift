import Foundation
import ImageIO
import UniformTypeIdentifiers

struct RotationWriter {
    enum WriteError: LocalizedError {
        case unreadableImage(String)
        case unsupportedFormat(String)
        case invalidSidecar(String)
        case metadataFailed(String)

        var errorDescription: String? {
            switch self {
            case .unreadableImage(let name):
                return String(localized: "Could not read \(name)", bundle: Localization.bundle)
            case .unsupportedFormat(let name):
                return String(localized: "Cannot save rotation to \(name) without re-encoding its pixels", bundle: Localization.bundle)
            case .invalidSidecar(let name):
                return String(localized: "Could not read XMP metadata in \(name)", bundle: Localization.bundle)
            case .metadataFailed(let name):
                return String(localized: "Could not update orientation metadata in \(name)", bundle: Localization.bundle)
            }
        }
    }

    nonisolated static func normalizedTurns(_ turns: Int) -> Int {
        ((turns % 4) + 4) % 4
    }

    nonisolated static func compose(orientation: Int, quarterTurns: Int) -> Int {
        let cycle = [2, 7, 4, 5].contains(orientation) ? [2, 7, 4, 5] : [1, 6, 3, 8]
        let index = cycle.firstIndex(of: orientation) ?? 0
        return cycle[(index + normalizedTurns(quarterTurns)) % 4]
    }

    /// Only the rotation component is compared. A sidecar never changes mirroring.
    nonisolated static func delta(from: Int, to: Int) -> Int {
        func rotation(_ orientation: Int) -> Int {
            switch orientation {
            case 6, 7: return 1
            case 3, 4: return 2
            case 8, 5: return 3
            default: return 0
            }
        }
        return normalizedTurns(rotation(to) - rotation(from))
    }

    nonisolated static func isRAW(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .rawImage) == true
    }

    nonisolated static func sidecarURL(for url: URL) -> URL {
        let base = url.deletingPathExtension()
        let defaultURL = base.appendingPathExtension("xmp")
        guard FileManager.default.fileExists(atPath: defaultURL.path)
                || FileManager.default.fileExists(atPath: base.appendingPathExtension("XMP").path) else {
            return defaultURL
        }
        let directory = base.deletingLastPathComponent()
        // fileExists accepts the wrong case on most Mac volumes. Keep the stored spelling.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for ext in ["xmp", "XMP"] {
            let name = "\(base.lastPathComponent).\(ext)"
            if names.contains(name) { return directory.appendingPathComponent(name) }
        }
        return defaultURL
    }

    nonisolated static func embeddedOrientation(in source: CGImageSource) -> Int {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    }

    nonisolated static func sidecarOrientation(for url: URL) -> Int? {
        let base = url.deletingPathExtension()
        for ext in ["xmp", "XMP"] {
            guard let data = try? Data(contentsOf: base.appendingPathExtension(ext)),
                  let metadata = CGImageMetadataCreateFromXMPData(data as CFData) else { continue }
            return orientation(in: metadata)
        }
        return nil
    }

    nonisolated static func apply(quarterTurns: Int, to url: URL) throws {
        guard normalizedTurns(quarterTurns) != 0 else { return }
        if isRAW(url) {
            try writeSidecar(quarterTurns: quarterTurns, to: url)
        } else {
            try writeInPlace(quarterTurns: quarterTurns, to: url)
        }
    }

    struct BatchResult: Sendable {
        var savedURLs: [URL] = []
        var failedURLs: [URL] = []
        var firstError: String?

        var savedCount: Int { savedURLs.count }
        var failedCount: Int { failedURLs.count }

        func message(bundle: Bundle = Localization.bundle, locale: Locale = .current) -> String {
            if failedCount > 0 {
                return String(localized: "Saved \(savedCount), failed \(failedCount)", bundle: bundle, locale: locale)
            }
            return String(localized: "Rotation saved for \(savedCount) photos", bundle: bundle, locale: locale)
        }
    }

    /// Coordinate cache barriers on the main actor; write one file at a time off it.
    @MainActor
    static func applyBatch(
        quarterTurns: Int, to urls: [URL], imageLoader: ImageLoader,
        onSaved: (URL) -> Void = { _ in }
    ) async -> BatchResult {
        var result = BatchResult()
        for url in urls {
            guard imageLoader.beginRotationWrite(for: url) else {
                result.failedURLs.append(url)
                continue
            }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try apply(quarterTurns: quarterTurns, to: url)
                }.value
                imageLoader.applySavedRotation(quarterTurns: quarterTurns, for: url)
                onSaved(url)
                result.savedURLs.append(url)
            } catch {
                imageLoader.cancelRotationWrite(for: url)
                result.failedURLs.append(url)
                if result.firstError == nil { result.firstError = error.localizedDescription }
            }
        }
        return result
    }

    private nonisolated static func orientation(in metadata: CGImageMetadata) -> Int? {
        guard let value = CGImageMetadataCopyStringValueWithPath(
            metadata, nil, "tiff:Orientation" as CFString
        ) else { return nil }
        // An existing but invalid orientation counts as 1, rather than falling back to RAW.
        let orientation = Int(value as String) ?? 1
        return (1...8).contains(orientation) ? orientation : 1
    }

    private nonisolated static func writeSidecar(quarterTurns: Int, to url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WriteError.unreadableImage(url.lastPathComponent)
        }
        let sidecar = sidecarURL(for: url)
        let metadata: CGMutableImageMetadata
        if FileManager.default.fileExists(atPath: sidecar.path) {
            let data = try Data(contentsOf: sidecar)
            guard let existing = CGImageMetadataCreateFromXMPData(data as CFData),
                  let mutable = CGImageMetadataCreateMutableCopy(existing) else {
                throw WriteError.invalidSidecar(sidecar.lastPathComponent)
            }
            metadata = mutable
        } else {
            metadata = CGImageMetadataCreateMutable()
        }

        let embedded = CGImageSourceCreateWithURL(url as CFURL, nil).map { embeddedOrientation(in: $0) } ?? 1
        let updated = compose(orientation: orientation(in: metadata) ?? embedded, quarterTurns: quarterTurns)
        guard CGImageMetadataSetValueWithPath(metadata, nil, "tiff:Orientation" as CFString, updated as CFNumber),
              let data = CGImageMetadataCreateXMPData(metadata, nil) else {
            throw WriteError.metadataFailed(sidecar.lastPathComponent)
        }
        try (data as Data).write(to: sidecar, options: .atomic)
    }

    private nonisolated static func writeInPlace(quarterTurns: Int, to url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source), CGImageSourceGetCount(source) > 0 else {
            throw WriteError.unreadableImage(url.lastPathComponent)
        }
        let updated = compose(orientation: embeddedOrientation(in: source), quarterTurns: quarterTurns)
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".rawcull-rotation-\(UUID().uuidString)")
            .appendingPathExtension(url.pathExtension)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL, type, CGImageSourceGetCount(source), nil
        ) else { throw WriteError.unsupportedFormat(url.lastPathComponent) }

        let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: updated]
        if var tiff = original?[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = updated
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        CGImageDestinationSetProperties(destination, properties as CFDictionary)
        // CopyImageSource has a dedicated orientation option and preserves the compressed pixels.
        let options = [kCGImageDestinationOrientation: updated] as CFDictionary
        guard CGImageDestinationCopyImageSource(destination, source, options, nil),
              let written = CGImageSourceCreateWithURL(temporaryURL as CFURL, nil),
              embeddedOrientation(in: written) == updated else {
            throw WriteError.unsupportedFormat(url.lastPathComponent)
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
    }
}
