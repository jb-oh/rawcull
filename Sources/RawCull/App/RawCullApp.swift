import SwiftUI

@main
struct RawCullApp: App {
    @State private var session = CullSession()
    @State private var shortcuts = KeyBindingStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(shortcuts)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            FolderCommands()
        }

        Settings {
            SettingsView()
                .environment(shortcuts)
                .environment(session)
        }
    }
}

private struct FolderCommands: Commands {
    @FocusedValue(\.closeFolder) private var closeFolder

    var body: some Commands {
        // Precede the standard Close command so an open folder handles Command W first.
        CommandGroup(before: .newItem) {
            Button("Close Folder") {
                closeFolder?()
            }
            // Release the equivalent when disabled so the standard window Close handles it.
            .keyboardShortcut(closeFolder == nil ? nil : KeyboardShortcut("w", modifiers: .command))
            .disabled(closeFolder == nil)
        }
    }
}

private struct CloseFolderFocusedValueKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var closeFolder: (() -> Void)? {
        get { self[CloseFolderFocusedValueKey.self] }
        set { self[CloseFolderFocusedValueKey.self] = newValue }
    }
}
