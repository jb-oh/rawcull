import AppKit
import SwiftUI

enum AppState {
    case welcome
    case culling
    case done
}

struct ContentView: View {
    @Environment(CullSession.self) private var session
    @State private var appState: AppState = .welcome
    @State private var imageLoader = ImageLoader()
    @State private var rootURL: URL?
    @State private var folderTree: FolderNode?
    @State private var switchTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch appState {
            case .welcome:
                WelcomeView(onFolderSelected: startCulling)
            case .culling:
                CullingView(
                    folderTree: folderTree,
                    onSelectFolder: switchFolder,
                    onFinish: { appState = .done },
                    onCloseFolder: closeFolder
                )
                .environment(imageLoader)
            case .done:
                SummaryView(
                    onGoBack: { appState = .culling },
                    onComplete: continueAfterMove
                )
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            session.flushSave()
        }
    }

    // MARK: - Flow

    private func startCulling(folderURL: URL, fileURLs: [URL]) {
        rootURL = folderURL
        session.load(folderURL: folderURL, fileURLs: fileURLs)
        imageLoader.startLoading(items: session.items, currentIndex: session.currentIndex)
        appState = .culling
        rebuildTree()
    }

    /// Switches the session to `url` (top-level photos only). Ignores a click
    /// on the folder that is already loaded. A newer click cancels an older
    /// in-flight switch so only the last selection wins.
    private func switchFolder(_ url: URL) {
        guard url.path != session.folderURL?.path else { return }
        loadFolder(url)
    }

    private func loadFolder(_ url: URL) {
        switchTask?.cancel()
        switchTask = Task {
            let fileURLs = await Task.detached(priority: .userInitiated) {
                FolderScanner.scan(folderURL: url)
            }.value
            guard !Task.isCancelled else { return }

            imageLoader.clearAll()
            session.load(folderURL: url, fileURLs: fileURLs)
            imageLoader.startLoading(items: session.items, currentIndex: session.currentIndex)
        }
    }

    /// After Move Files: stay on the tree, reload the current folder (moved
    /// files are gone) and rebuild the tree so Picks/ and Rejects/ appear.
    private func continueAfterMove() {
        guard let current = session.folderURL else {
            closeFolder()
            return
        }
        appState = .culling
        loadFolder(current)
        rebuildTree()
    }

    private func closeFolder() {
        switchTask?.cancel()
        switchTask = nil
        session.flushSave()
        session.reset()
        imageLoader.clearAll()
        rootURL = nil
        folderTree = nil
        appState = .welcome
    }

    private func rebuildTree() {
        guard let rootURL else {
            folderTree = nil
            return
        }
        Task.detached(priority: .userInitiated) {
            let tree = FolderScanner.folderTree(rootURL: rootURL)
            await MainActor.run {
                // Ignore a stale result if the folder was closed meanwhile.
                guard self.rootURL == rootURL else { return }
                folderTree = tree
            }
        }
    }
}
