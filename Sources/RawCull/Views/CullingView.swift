import AppKit
import FavrenUI
import SwiftUI

struct CullingView: View {
    @Environment(CullSession.self) private var session
    @Environment(ImageLoader.self) private var imageLoader
    @Environment(KeyBindingStore.self) private var shortcuts
    let folderTree: FolderNode?
    let onSelectFolder: (URL) -> Void
    let onFinish: () -> Void
    @Binding var expandedFolderURLs: Set<URL>
    /// Non-nil while a folder switch is in flight. Culling keys and Finish are
    /// blocked for the whole switch; the overlay itself appears after a delay.
    let loading: FolderLoading?

    @State private var isZoomed = false
    @State private var rotationPreview = RotationPreview()
    @State private var showSidebar = true
    @State private var showFolderTree = true
    @State private var rotationFeedback: RotationFeedback?
    @AppStorage("folderTreeWidth") private var folderTreeWidth = 260.0
    @AppStorage("thumbnailSidebarWidth") private var thumbnailSidebarWidth = 120.0

    private var boundedFolderTreeWidth: Double {
        min(max(folderTreeWidth, 200), 420)
    }

    private var boundedThumbnailSidebarWidth: Double {
        min(max(thumbnailSidebarWidth, 100), 240)
    }

    private struct RotationFeedback {
        let id = UUID()
        let url: URL?
        let message: String
        let failed: Bool
    }

    var body: some View {
        HStack(spacing: 0) {
            // Folder tree
            if showFolderTree, let folderTree {
                FolderTreePanel(
                    root: folderTree,
                    selectedURL: session.folderURL,
                    expandedURLs: $expandedFolderURLs,
                    onSelect: onSelectFolder
                )
                .frame(width: boundedFolderTreeWidth)

                Divider()
                    .padding(.horizontal, 3)
                    .overlay {
                        PanelResizeHandle(width: Binding(
                            get: { boundedFolderTreeWidth },
                            set: { folderTreeWidth = min(max($0, 200), 420) }
                        ))
                    }
            }

            HStack(spacing: 0) {
                // Thumbnail sidebar
                if showSidebar {
                    ThumbnailSidebar(
                        imageHeight: boundedThumbnailSidebarWidth * 75 / 120,
                        previewRotation: { rotationPreview.turns(for: $0) },
                        onRotate: { turns, targets in
                            writeRotation(quarterTurns: turns, to: targets.map(\.url))
                        }
                    )
                    .frame(width: boundedThumbnailSidebarWidth)

                    Divider()
                        .padding(.horizontal, 3)
                        .overlay {
                            PanelResizeHandle(width: Binding(
                                get: { boundedThumbnailSidebarWidth },
                                set: { thumbnailSidebarWidth = min(max($0, 100), 240) }
                            ))
                        }
                }

                // Main content
                VStack(spacing: 0) {
                    // Photo
                    Group {
                        if session.count == 0 {
                            EmptyFolderView()
                        } else {
                            PhotoView(
                                image: currentPreview,
                                decision: session.currentItem?.decision ?? .undecided,
                                isZoomed: $isZoomed,
                                rotationQuarterTurns: session.currentItem.map { rotationPreview.turns(for: $0.url) } ?? 0
                            )
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if let feedback = rotationFeedback,
                           feedback.url == nil || feedback.url == session.currentItem?.url {
                            FavrenBadge(feedback.message, tone: feedback.failed ? .danger : .success)
                                .padding(16)
                                .transition(.opacity)
                                .allowsHitTesting(false)
                        }
                    }

                    Divider()

                    // Status bar
                    StatusBar(
                        currentIndex: session.currentIndex,
                        totalCount: session.count,
                        decision: session.currentItem?.decision ?? .undecided,
                        pickCount: session.pickCount,
                        rejectCount: session.rejectCount,
                        undecidedCount: session.undecidedCount,
                        selectionCount: session.selectionCount
                    )
                }
            }
            // Leaves the folder tree clickable so another folder can be picked.
            .overlay {
                if let loading, loading.showsOverlay {
                    FolderLoadingOverlay(folderName: loading.folderName, foundCount: loading.foundCount)
                }
            }
        }
        // Keep scrolling panels inside the content area below the title bar.
        .clipped()
        .background {
            KeyboardEventMonitor { event in
                handleKeyDown(event)
            }
        }
        .background {
            WindowFocusActivator()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Finish") {
                    onFinish()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(session.count == 0 || loading != nil)
            }
        }
        .toolbarBackground(FavrenColors.surface, for: .windowToolbar)
        .modifier(CullingToolbarBackground())
        .onChange(of: session.currentIndex) { _, newIndex in
            resetView()
            imageLoader.prefetch(around: newIndex)
        }
        .onChange(of: session.selectedItemIDs) { _, _ in
            rotationPreview.reset()
        }
        .onChange(of: session.folderURL) { _, _ in
            resetView()
        }
        .onChange(of: isZoomed) { _, newValue in
            guard newValue, let item = session.currentItem else { return }
            imageLoader.loadDetailIfNeeded(for: item.url)
        }
        .onAppear {
            imageLoader.prefetch(around: session.currentIndex)
        }
        .task(id: rotationFeedback?.id) {
            guard let id = rotationFeedback?.id else { return }
            do { try await Task.sleep(for: .seconds(1.5)) }
            catch { return }
            guard rotationFeedback?.id == id else { return }
            withAnimation(.easeOut(duration: 0.2)) { rotationFeedback = nil }
        }
    }

    private var currentPreview: NSImage? {
        guard let item = session.currentItem else { return nil }
        if isZoomed, let detail = imageLoader.detail(for: item.url) {
            return detail
        }

        // Try preview first, fall back to thumbnail.
        return imageLoader.preview(for: item.url) ?? imageLoader.thumbnail(for: item.url)
    }

    private func navigateNext() {
        rotationPreview.reset()
        session.next()
    }

    private func navigatePrevious() {
        rotationPreview.reset()
        session.previous()
    }

    private func rotateCounterClockwise() {
        rotationPreview.rotate(by: -1)
    }

    private func rotateClockwise() {
        rotationPreview.rotate(by: 1)
    }

    private func resetView() {
        isZoomed = false
        rotationPreview.reset()
    }

    private func saveRotation() {
        let urls = session.actionTargets.map(\.url)
        guard !urls.isEmpty, let write = rotationPreview.beginSave() else { return }
        writeRotation(quarterTurns: write.quarterTurns, to: urls, pendingWrite: write)
    }

    private func writeRotation(
        quarterTurns: Int, to urls: [URL], pendingWrite: RotationPreview.Write? = nil
    ) {
        guard !urls.isEmpty else { return }
        Task {
            let result = await RotationWriter.applyBatch(
                quarterTurns: quarterTurns, to: urls, imageLoader: imageLoader
            ) { url in
                if let pendingWrite { rotationPreview.didSave(url, write: pendingWrite) }
            }
            if let pendingWrite { rotationPreview.finish(pendingWrite, savedCount: result.savedCount) }

            let isBatch = urls.count > 1
            let message: String
            if isBatch {
                message = result.message()
            } else if let error = result.firstError {
                message = error
            } else if let url = result.savedURLs.first {
                message = RotationWriter.isRAW(url)
                    ? String(localized: "Rotation saved to \(RotationWriter.sidecarURL(for: url).lastPathComponent)", bundle: Localization.bundle)
                    : String(localized: "Rotation saved", bundle: Localization.bundle)
            } else {
                // A single in-flight file keeps the existing silent no-op behaviour.
                return
            }
            withAnimation(.easeOut(duration: 0.2)) {
                rotationFeedback = RotationFeedback(
                    url: isBatch ? nil : urls[0], message: message, failed: result.failedCount > 0
                )
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            return false
        }
        guard !shortcuts.isRecording else { return false }
        if event.keyCode == 53 { return session.collapseSelection() }

        // Keys would act on the previous folder until the switch lands. Swallow
        // them so an unhandled key does not beep.
        guard loading == nil else { return true }

        guard let action = shortcuts.action(for: event.keyCode) else { return false }
        switch action {
        case .previous:
            navigatePrevious()
        case .next:
            navigateNext()
        case .pick:
            session.markPick()
        case .unmark:
            session.unmarkCurrent()
        case .reject:
            session.markReject()
        case .rotateCounterClockwise:
            rotateCounterClockwise()
        case .resetView:
            resetView()
        case .rotateClockwise:
            rotateClockwise()
        case .zoom:
            isZoomed.toggle()
        case .saveRotation:
            saveRotation()
        case .toggleThumbnails:
            showSidebar.toggle()
        case .toggleFolderTree:
            showFolderTree.toggle()
        }
        return true
    }
}

/// Tracks the pending preview separately from each file already saved in a running batch.
struct RotationPreview {
    struct Write {
        let id = UUID()
        let quarterTurns: Int
    }

    private(set) var quarterTurns = 0
    private var write: Write?
    private var savedURLs: Set<URL> = []

    mutating func rotate(by turns: Int) {
        quarterTurns = RotationWriter.normalizedTurns(quarterTurns + turns)
    }

    func turns(for url: URL) -> Int {
        RotationWriter.normalizedTurns(quarterTurns - (savedURLs.contains(url) ? write?.quarterTurns ?? 0 : 0))
    }

    mutating func reset() {
        quarterTurns = 0
        write = nil
        savedURLs = []
    }

    mutating func beginSave() -> Write? {
        guard quarterTurns != 0, write == nil else { return nil }
        let pending = Write(quarterTurns: quarterTurns)
        write = pending
        return pending
    }

    mutating func didSave(_ url: URL, write savedWrite: Write) {
        guard write?.id == savedWrite.id else { return }
        savedURLs.insert(url)
    }

    mutating func finish(_ finishedWrite: Write, savedCount: Int) {
        guard write?.id == finishedWrite.id else { return }
        if savedCount > 0 {
            quarterTurns = RotationWriter.normalizedTurns(quarterTurns - finishedWrite.quarterTurns)
        }
        write = nil
        savedURLs = []
    }
}

private struct CullingToolbarBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            visibleBackground(content)
                // Inherited by both the folder list and thumbnail scroll view.
                .scrollEdgeEffectHidden(for: .top)
        } else {
            visibleBackground(content)
        }
    }

    @ViewBuilder
    private func visibleBackground(_ content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            content.toolbarBackground(.visible, for: .windowToolbar)
        }
    }
}

private struct PanelResizeHandle: NSViewRepresentable {
    @Binding var width: Double

    func makeNSView(context: Context) -> PanelResizeView {
        PanelResizeView()
    }

    func updateNSView(_ nsView: PanelResizeView, context: Context) {
        nsView.width = width
        nsView.onResize = { width = $0 }
    }
}

private final class PanelResizeView: NSView {
    var width = 0.0
    var onResize: ((Double) -> Void)?
    private var initialWidth = 0.0
    private var initialMouseX: CGFloat = 0

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        initialWidth = width
        initialMouseX = event.locationInWindow.x
    }

    override func mouseDragged(with event: NSEvent) {
        // Window coordinates stay fixed as resizing moves the divider itself.
        onResize?(initialWidth + Double(event.locationInWindow.x - initialMouseX))
    }
}

private struct EmptyFolderView: View {
    var body: some View {
        ZStack {
            Color.black
            ContentUnavailableView(
                "No photos in this folder",
                systemImage: "photo",
                description: Text("Pick another folder from the tree on the left.")
            )
            .foregroundStyle(.white)
        }
    }
}

private struct WindowFocusActivator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        FocusActivatingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class FocusActivatingView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        activateWindow()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        activateWindow()
    }

    private func activateWindow() {
        guard let window else { return }

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeMain()
            window.makeFirstResponder(window.contentView)
        }
    }
}
