import AppKit
import FavrenUI
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
    @State private var scannedCount = 0
    @State private var showsLoadingOverlay = false
    /// Bumped by every `loadFolder`, so progress hops and the overlay timer of
    /// a superseded load (even one for the same URL) can tell they are stale.
    @State private var loadGeneration = 0
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
                    expandedFolderURLs: $expandedFolderURLs,
                    loading: folderLoading
                )
                .environment(imageLoader)
            case .done:
                SummaryView(
                    onGoBack: { appState = .culling },
                    onComplete: continueAfterMove,
                    isContinuing: isContinuing,
                    rootURL: rootURL
                )
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .favrenWindowBackground()
        .focusedSceneValue(\.closeFolder, closeFolderAction)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            session.flushSave()
        }
    }

    /// Non-nil while a folder switch is in flight.
    private var folderLoading: FolderLoading? {
        guard let pendingFolderURL else { return nil }
        return FolderLoading(
            folderName: pendingFolderURL.lastPathComponent,
            foundCount: scannedCount,
            showsOverlay: showsLoadingOverlay
        )
    }

    // MARK: - Flow

    private var closeFolderAction: (() -> Void)? {
        guard rootURL != nil else { return nil }
        return closeFolder
    }

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
        scannedCount = 0
        loadGeneration += 1
        let generation = loadGeneration

        // Show the overlay only if the load is still pending after a short
        // delay. A superseding load keeps an already visible overlay up.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard loadGeneration == generation, pendingFolderURL != nil else { return }
            showsLoadingOverlay = true
        }

        switchTask = Task {
            let scanTask = Task.detached(priority: .userInitiated) {
                FolderScanner.scan(folderURL: url) { count in
                    Task { @MainActor in
                        guard loadGeneration == generation, pendingFolderURL != nil else { return }
                        scannedCount = count
                    }
                }
            }
            // A detached task does not inherit cancellation, so forward it.
            let fileURLs = await withTaskCancellationHandler {
                await scanTask.value
            } onCancel: {
                scanTask.cancel()
            }
            guard !Task.isCancelled else { return }

            imageLoader.clearAll()
            session.load(folderURL: url, fileURLs: fileURLs)
            imageLoader.startLoading(items: session.items, currentIndex: session.currentIndex)
            if pendingFolderURL?.path == url.path {
                pendingFolderURL = nil
                showsLoadingOverlay = false
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
        // A directly opened sorted folder can send photos outside the current tree.
        if let rootURL, let sortedRoot = SortedFolder(folderURL: rootURL) {
            self.rootURL = sortedRoot.parentURL
            expandedFolderURLs.insert(sortedRoot.parentURL)
        }
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
        showsLoadingOverlay = false
        scannedCount = 0
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
