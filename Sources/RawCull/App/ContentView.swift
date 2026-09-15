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
    @State private var pendingFolderURL: URL?
    @State private var expandedFolderURLs: Set<URL> = []
    @State private var isContinuing = false

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
                    onCloseFolder: closeFolder,
                    expandedFolderURLs: $expandedFolderURLs
                )
                .environment(imageLoader)
            case .done:
                SummaryView(
                    onGoBack: { appState = .culling },
                    onComplete: continueAfterMove,
                    isContinuing: isContinuing
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
        expandedFolderURLs.insert(folderURL)
        session.load(folderURL: folderURL, fileURLs: fileURLs)
        imageLoader.startLoading(items: session.items, currentIndex: session.currentIndex)
        appState = .culling
        rebuildTree()
    }

    /// Switches the session to `url` (top-level photos only). Ignores a click
    /// on the folder that is already loaded or already the target of an
    /// in-flight switch. A newer click cancels an older in-flight switch so
    /// only the last selection wins.
    private func switchFolder(_ url: URL) {
        guard url.path != (pendingFolderURL ?? session.folderURL)?.path else { return }
        loadFolder(url)
    }

    private func loadFolder(_ url: URL, onLoaded: (() -> Void)? = nil) {
        switchTask?.cancel()
        pendingFolderURL = url
        switchTask = Task {
            let fileURLs = await Task.detached(priority: .userInitiated) {
                FolderScanner.scan(folderURL: url)
            }.value
            guard !Task.isCancelled else { return }

            imageLoader.clearAll()
            session.load(folderURL: url, fileURLs: fileURLs)
            imageLoader.startLoading(items: session.items, currentIndex: session.currentIndex)
            if pendingFolderURL?.path == url.path {
                pendingFolderURL = nil
            }
            onLoaded?()
        }
    }

    /// After Move Files: stay on the tree, reload the current folder (moved
    /// files are gone) and rebuild the tree so Picks/ and Rejects/ appear.
    /// Waits for the reload to land before showing the culling view again,
    /// so a stray keypress can't recreate a session file for the folder
    /// `deleteSessionFile` just removed.
    private func continueAfterMove() {
        guard let current = session.folderURL else {
            closeFolder()
            return
        }
        isContinuing = true
        expandedFolderURLs.insert(current)
        loadFolder(current) {
            isContinuing = false
            appState = .culling
        }
        rebuildTree()
    }

    private func closeFolder() {
        switchTask?.cancel()
        switchTask = nil
        pendingFolderURL = nil
        session.flushSave()
        session.reset()
        imageLoader.clearAll()
        rootURL = nil
        folderTree = nil
        expandedFolderURLs = []
        isContinuing = false
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
