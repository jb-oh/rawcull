import AppKit
import SwiftUI

@main
struct RawCullApp: App {
    @State private var session = CullSession()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}
