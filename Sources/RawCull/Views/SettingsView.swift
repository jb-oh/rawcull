import AppKit
import FavrenUI
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            LanguageSettingsView()
                .tabItem { Label("Language", systemImage: "globe") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 680, height: 620)
    }
}

private struct LanguageSettingsView: View {
    @Environment(CullSession.self) private var session
    @State private var language = LanguagePreferenceStore()
    @State private var restartError: String?
    @State private var isRestarting = false

    var body: some View {
        @Bindable var language = language
        Form {
            Section("Language") {
                Picker("Language", selection: $language.selection) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Text("Restart RawCull to apply the language change.")
                    .font(.callout)
                    .foregroundStyle(FavrenColors.onSurfaceVariant)
                Button("Restart Now") {
                    restart()
                }
                .disabled(isRestarting)
            }
        }
        .formStyle(.grouped)
        .alert("Could Not Restart RawCull", isPresented: Binding(
            get: { restartError != nil },
            set: { if !$0 { restartError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restartError ?? "")
        }
    }

    private func restart() {
        session.flushSave()
        UserDefaults.standard.synchronize()
        isRestarting = true
        Task {
            do {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = true
                _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
                NSApp.terminate(nil)
            } catch {
                isRestarting = false
                restartError = error.localizedDescription
            }
        }
    }
}

private struct ShortcutsSettingsView: View {
    @Environment(KeyBindingStore.self) private var shortcuts
    @State private var conflict: Conflict?

    private struct Conflict {
        let key: KeyBinding
        let previous: CullAction
        let current: CullAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Use plain keys without modifiers. Escape cancels recording.")
                .font(.callout)
                .foregroundStyle(FavrenColors.onSurfaceVariant)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(CullAction.allCases) { action in
                        shortcutRow(action)
                        if action != CullAction.allCases.last {
                            Divider()
                        }
                    }
                }
                .padding(4)
            }

            HStack {
                Spacer()
                Button("Restore Defaults") {
                    shortcuts.restoreDefaults()
                    conflict = nil
                }
            }
        }
        .padding(20)
        .background {
            KeyboardEventMonitor(onKeyDown: recordKey)
        }
        .onDisappear { shortcuts.cancelRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            shortcuts.cancelRecording()
        }
    }

    private func shortcutRow(_ action: CullAction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(action.displayName)
                Spacer(minLength: 8)
                if shortcuts.recordingAction == action {
                    Button("Cancel") { shortcuts.cancelRecording() }
                } else {
                    Button("Add Key") {
                        conflict = nil
                        shortcuts.beginRecording(for: action)
                    }
                }
            }

            if shortcuts.keys(for: action).isEmpty {
                Text("None")
                    .foregroundStyle(FavrenColors.onSurfaceVariant)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading) {
                    ForEach(shortcuts.keys(for: action)) { key in
                        Button {
                            shortcuts.remove(keyCode: key.keyCode, from: action)
                            conflict = nil
                        } label: {
                            HStack(spacing: 3) {
                                FavrenKeyCap(key.label)
                                Image(systemName: "xmark")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(Text("Remove \(key.label) from \(action.displayName)"))
                        .accessibilityLabel(Text("Remove \(key.label) from \(action.displayName)"))
                    }
                }
            }

            if shortcuts.recordingAction == action {
                Text("Press a key…")
                    .font(.caption)
                    .foregroundStyle(FavrenColors.primary)
            }
            if let conflict, conflict.current == action {
                Text("\(conflict.key.label) moved from \(conflict.previous.displayName) to \(action.displayName).")
                    .font(.caption)
                    .foregroundStyle(FavrenColors.onSurfaceVariant)
            }
        }
    }

    private func recordKey(_ event: NSEvent) -> Bool {
        guard let action = shortcuts.recordingAction else { return false }
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            return false
        }
        if event.keyCode == 53 {
            shortcuts.cancelRecording()
            return true
        }
        guard let key = KeyBinding(keyCode: event.keyCode) else { return true }
        if let previous = shortcuts.add(keyCode: key.keyCode, to: action) {
            conflict = Conflict(key: key, previous: previous, current: action)
        }
        shortcuts.cancelRecording()
        return true
    }
}
