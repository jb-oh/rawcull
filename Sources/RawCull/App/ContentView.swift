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

    var body: some View {
        Group {
            switch appState {
            case .welcome:
                WelcomeView(onFolderSelected: startCulling)
            case .culling:
                CullingView(
                    onFinish: { appState = .done }
                )
                .environment(imageLoader)
            case .done:
                SummaryView(
                    onGoBack: { appState = .culling },
                    onComplete: {
                        session.reset()
                        imageLoader.clearAll()
                        appState = .welcome
                    }
                )
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            session.flushSave()
        }
    }

    private func startCulling(folderURL: URL, fileURLs: [URL]) {
        session.load(folderURL: folderURL, fileURLs: fileURLs)
        imageLoader.startLoading(items: session.items, currentIndex: session.currentIndex)
        appState = .culling
    }
}
