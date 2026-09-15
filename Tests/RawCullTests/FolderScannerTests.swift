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

    @Test func folderTreeBuildsNestedFoldersInNaturalOrderSkippingHiddenAndFiles() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        for path in ["Day 10", "Day 2", "Day 2/Raw", "Day 2/Jpeg", ".hidden"] {
            try fileManager.createDirectory(
                at: tempDir.appendingPathComponent(path),
                withIntermediateDirectories: true
            )
        }
        fileManager.createFile(atPath: tempDir.appendingPathComponent("a.png").path, contents: Data())

        let tree = FolderScanner.folderTree(rootURL: tempDir)

        #expect(tree.url == tempDir)
        #expect(tree.name == tempDir.lastPathComponent)
        #expect(tree.children.map(\.name) == ["Day 2", "Day 10"])
        #expect(tree.children[0].children.map(\.name) == ["Jpeg", "Raw"])
        #expect(tree.children[1].children.isEmpty)
    }

    @Test func folderTreeDoesNotFollowSymbolicLinks() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        try fileManager.createDirectory(
            at: tempDir.appendingPathComponent("Real"),
            withIntermediateDirectories: true
        )
        // A link back to the root would recurse forever if followed.
        try fileManager.createSymbolicLink(
            at: tempDir.appendingPathComponent("Link"),
            withDestinationURL: tempDir
        )

        let tree = FolderScanner.folderTree(rootURL: tempDir)

        #expect(tree.children.map(\.name) == ["Real"])
    }

    @Test func folderNodeFirstWhereSearchesDepthFirst() throws {
        let leaf = FolderNode(url: URL(fileURLWithPath: "/r/a/b"), name: "b", children: [])
        let mid = FolderNode(url: URL(fileURLWithPath: "/r/a"), name: "a", children: [leaf])
        let root = FolderNode(url: URL(fileURLWithPath: "/r"), name: "r", children: [mid])

        #expect(root.first(where: { $0.name == "b" })?.url == leaf.url)
        #expect(root.first(where: { $0.name == "zzz" }) == nil)
    }
}
