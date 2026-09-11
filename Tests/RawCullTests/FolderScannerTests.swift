import Foundation
import Testing
@testable import RawCull

struct FolderScannerTests {

    @Test func scanReturnsOnlySupportedTopLevelFilesInNaturalOrder() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let subDir = tempDir.appendingPathComponent("Sub")
        try fileManager.createDirectory(at: subDir, withIntermediateDirectories: true)

        let filenames = [
            "a.png", "b.webp", "c.pef", "d.JPG", "e.svg", "f.txt",
            ".hidden.png", ".rawcull-session.json"
        ]
        for name in filenames {
            fileManager.createFile(atPath: tempDir.appendingPathComponent(name).path, contents: Data())
        }
        fileManager.createFile(atPath: subDir.appendingPathComponent("g.png").path, contents: Data())

        let result = FolderScanner.scan(folderURL: tempDir)
        let names = result.map { $0.lastPathComponent }

        #expect(names == ["a.png", "b.webp", "c.pef", "d.JPG"])
    }

    @Test(arguments: ["png", "gif", "heic", "webp", "arw", "pef", "srw"])
    func isSupportedTrueForImageExtensions(ext: String) throws {
        let url = URL(fileURLWithPath: "/tmp/test-file.\(ext)")
        #expect(FolderScanner.isSupported(url))
    }

    @Test(arguments: ["svg", "pdf", "txt", "mov"])
    func isSupportedFalseForNonDecodableExtensions(ext: String) throws {
        let url = URL(fileURLWithPath: "/tmp/test-file.\(ext)")
        #expect(!FolderScanner.isSupported(url))
    }

    @Test func isSupportedFalseForNoExtension() throws {
        let url = URL(fileURLWithPath: "/tmp/test-file")
        #expect(!FolderScanner.isSupported(url))
    }
}
