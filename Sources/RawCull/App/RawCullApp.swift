import SwiftUI

@main
struct RawCullApp: App {
    @State private var session = CullSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
    }
}
