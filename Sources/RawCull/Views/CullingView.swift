import AppKit
import SwiftUI

struct CullingView: View {
    @Environment(CullSession.self) private var session
    @Environment(ImageLoader.self) private var imageLoader
    let folderTree: FolderNode?
    let onSelectFolder: (URL) -> Void
    let onFinish: () -> Void
    let onCloseFolder: () -> Void

    @State private var isZoomed = false
    @State private var rotationQuarterTurns = 0
    @State private var showSidebar = true
    @State private var showFolderTree = true

    var body: some View {
        HStack(spacing: 0) {
            // Folder tree
            if showFolderTree, let folderTree {
                FolderTreePanel(
                    root: folderTree,
                    selectedURL: session.folderURL,
                    onSelect: onSelectFolder
                )
                .frame(width: 200)

                Divider()
            }

            // Thumbnail sidebar
            if showSidebar {
                ThumbnailSidebar()
                    .frame(width: 120)

                Divider()
            }

            // Main content
            VStack(spacing: 0) {
                // Photo
                if session.count == 0 {
                    EmptyFolderView()
                } else {
                    PhotoView(
                        image: currentPreview,
                        decision: session.currentItem?.decision ?? .undecided,
                        isZoomed: $isZoomed,
                        rotationQuarterTurns: rotationQuarterTurns
                    )
                }

                Divider()

                // Status bar
                StatusBar(
                    currentIndex: session.currentIndex,
                    totalCount: session.count,
                    decision: session.currentItem?.decision ?? .undecided,
                    pickCount: session.pickCount,
                    rejectCount: session.rejectCount
                )
            }
        }
        .background {
            KeyboardEventMonitor { event in
                handleKeyDown(event)
            }
        }
        .background {
            WindowFocusActivator()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Close Folder") {
                    onCloseFolder()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Finish") {
                    onFinish()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(session.count == 0)
            }
        }
        .onChange(of: session.currentIndex) { _, newIndex in
            resetView()
            imageLoader.prefetch(around: newIndex)
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
        session.next()
    }

    private func navigatePrevious() {
        session.previous()
    }

    private func rotateCounterClockwise() {
        rotationQuarterTurns = (rotationQuarterTurns + 3) % 4
    }

    private func rotateClockwise() {
        rotationQuarterTurns = (rotationQuarterTurns + 1) % 4
    }

    private func resetView() {
        isZoomed = false
        rotationQuarterTurns = 0
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return false
        }

        switch event.keyCode {
        case 123, 126:
            navigatePrevious()
            return true
        case 124, 125:
            navigateNext()
            return true
        case 0:
            session.markPick()
            return true
        case 1:
            session.unmarkCurrent()
            return true
        case 2:
            session.markReject()
            return true
        case 6:
            rotateCounterClockwise()
            return true
        case 7:
            resetView()
            return true
        case 8:
            rotateClockwise()
            return true
        case 49:
            isZoomed.toggle()
            return true
        default:
            break
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch characters {
        case "h":
            navigatePrevious()
            return true
        case "l":
            navigateNext()
            return true
        case "a", "ㅁ":
            session.markPick()
            return true
        case "s", "ㄴ":
            session.unmarkCurrent()
            return true
        case "d", "ㅇ":
            session.markReject()
            return true
        case "z", "ㅋ":
            rotateCounterClockwise()
            return true
        case "x", "ㅌ":
            resetView()
            return true
        case "c", "ㅊ":
            rotateClockwise()
            return true
        case "t":
            showSidebar.toggle()
            return true
        case "f", "ㄹ":
            showFolderTree.toggle()
            return true
        default:
            return false
        }
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

private struct KeyboardEventMonitor: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onKeyDown: (NSEvent) -> Bool
        private var monitor: Any?

        init(onKeyDown: @escaping (NSEvent) -> Bool) {
            self.onKeyDown = onKeyDown
        }

        func start() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.onKeyDown(event) ? nil : event
            }
        }

        func stop() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
