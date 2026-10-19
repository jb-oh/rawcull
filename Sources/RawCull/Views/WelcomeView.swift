import FavrenUI
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    let onFolderSelected: (URL, [URL]) -> Void

    @State private var isDragOver = false
    @State private var showResumeAlert = false
    @State private var showEmptyAlert = false
    @State private var isProcessingFolder = false
    @State private var pendingFolderURL: URL?
    @State private var pendingFileURLs: [URL] = []

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            FavrenEmptyState(
                systemImage: "photo.stack",
                title: String(localized: "Open a folder to start culling", bundle: Localization.bundle),
                subtitle: String(localized: "Drop a folder here or press Command O", bundle: Localization.bundle)
            ) {
                Button("Open Folder...") {
                    openFolder()
                }
                .buttonStyle(.favrenPrimary)
                .frame(maxWidth: 220)
                .keyboardShortcut("o", modifiers: .command)
                .disabled(isProcessingFolder)
            }

            if isProcessingFolder {
                ProgressView("Scanning folder...")
                    .controlSize(.small)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDragOver ? FavrenColors.primary : Color.clear,
                    style: StrokeStyle(lineWidth: 3, dash: [8])
                )
                .padding(16)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
            return true
        }
        .alert("Resume Session?", isPresented: $showResumeAlert) {
            Button("Resume") {
                if let folder = pendingFolderURL {
                    onFolderSelected(folder, pendingFileURLs)
                }
            }
            Button("Start Fresh") {
                if let folder = pendingFolderURL {
                    // Delete old session file
                    let sessionURL = folder.appendingPathComponent(".rawcull-session.json")
                    try? FileManager.default.removeItem(at: sessionURL)
                    onFolderSelected(folder, pendingFileURLs)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A previous culling session was found for this folder. Resume where you left off?")
        }
        .alert("No Photos Found", isPresented: $showEmptyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No supported image files or subfolders were found in the selected folder.")
        }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Select a folder containing photos", bundle: Localization.bundle)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        processFolder(url)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { return }

            DispatchQueue.main.async {
                processFolder(url)
            }
        }
    }

    private func processFolder(_ url: URL) {
        isProcessingFolder = true

        Task.detached(priority: .userInitiated) {
            let fileURLs = FolderScanner.scan(folderURL: url)
            let tree = FolderScanner.folderTree(rootURL: url)
            let hasExistingSession = FolderScanner.hasExistingSession(in: url)

            await MainActor.run {
                isProcessingFolder = false

                guard !fileURLs.isEmpty || !tree.children.isEmpty else {
                    showEmptyAlert = true
                    return
                }

                if hasExistingSession {
                    pendingFolderURL = url
                    pendingFileURLs = fileURLs
                    showResumeAlert = true
                } else {
                    onFolderSelected(url, fileURLs)
                }
            }
        }
    }
}
