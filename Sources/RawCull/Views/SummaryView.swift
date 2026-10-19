import FavrenUI
import SwiftUI

struct SummaryView: View {
    @Environment(CullSession.self) private var session
    let onGoBack: () -> Void
    let onComplete: () -> Void
    let isContinuing: Bool
    let rootURL: URL?

    @State private var isMoving = false
    @State private var moveProgress = 0.0
    @State private var moveError: String?
    @State private var moveComplete = false
    @State private var resultMessage = ""
    @State private var totals: SessionTotals?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(moveComplete ? FavrenSemantic.success : FavrenColors.onSurfaceVariant)

            Text(moveComplete ? String(localized: "Done!", bundle: Localization.bundle) : String(localized: "Culling Summary", bundle: Localization.bundle))
                .font(.largeTitle.bold())

            if moveComplete {
                Text(resultMessage)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Button("Continue") {
                    onComplete()
                }
                .buttonStyle(.favrenPrimary)
                .frame(maxWidth: 200)
                .disabled(isContinuing)

                if isContinuing {
                    ProgressView("Reloading folder...")
                        .controlSize(.small)
                }
            } else {
                // Stats
                FavrenSurface {
                    VStack(spacing: 12) {
                        SummaryRow(label: String(localized: "Picks", bundle: Localization.bundle), count: session.pickCount, color: FavrenSemantic.success, icon: "checkmark.circle.fill")
                        SummaryRow(label: String(localized: "Rejects", bundle: Localization.bundle), count: session.rejectCount, color: FavrenSemantic.danger, icon: "xmark.circle.fill")
                        SummaryRow(label: String(localized: "Undecided", bundle: Localization.bundle), count: session.undecidedCount, color: FavrenSemantic.neutral, icon: "questionmark.circle")
                    }
                }

                if session.undecidedCount > 0 {
                    Label(
                        Self.undecidedMessage(count: session.undecidedCount, folderURL: session.folderURL),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(FavrenSemantic.warning)
                    .font(.callout)
                }

                if let rootURL {
                    FavrenSurface {
                        VStack(spacing: 8) {
                            Text("All folders under \(rootURL.lastPathComponent)")
                                .font(.headline)
                            if let totals {
                                SummaryRow(label: String(localized: "Folders with sessions", bundle: Localization.bundle), count: totals.folders, color: FavrenSemantic.neutral, icon: "folder")
                                SummaryRow(label: String(localized: "Picks", bundle: Localization.bundle), count: totals.picks, color: FavrenSemantic.success, icon: "checkmark.circle.fill")
                                SummaryRow(label: String(localized: "Rejects", bundle: Localization.bundle), count: totals.rejects, color: FavrenSemantic.danger, icon: "xmark.circle.fill")
                                SummaryRow(label: String(localized: "Undecided", bundle: Localization.bundle), count: totals.undecided, color: FavrenSemantic.neutral, icon: "questionmark.circle")
                            } else {
                                ProgressView("Counting folders...")
                                    .controlSize(.small)
                            }
                        }
                    }
                }

                if isMoving {
                    ProgressView(value: moveProgress)
                        .frame(width: 300)
                    Text("Moving files...")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 16) {
                        Button("Go Back") {
                            onGoBack()
                        }
                        .buttonStyle(.favrenSecondary)
                        .frame(maxWidth: 200)

                        Button("Move Files") {
                            moveFiles()
                        }
                        .buttonStyle(.favrenPrimary)
                        .frame(maxWidth: 200)
                        .disabled(session.folderURL.map {
                            FileMover.moveCount(items: session.items, folderURL: $0) == 0
                        } ?? true)

                        if rootURL != nil {
                            Button("Move All Folders") {
                                moveAllFolders()
                            }
                            .buttonStyle(.favrenSecondary)
                            .frame(maxWidth: 200)
                            .disabled((totals?.filesToMove ?? 0) == 0)
                        }
                    }
                }

                if let error = moveError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(FavrenSemantic.danger)
                        .font(.callout)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .task(id: rootURL) {
            guard let rootURL else { return }
            // Flush first so the folder being reviewed is counted from disk.
            session.flushSave()
            let computed = await Task.detached(priority: .userInitiated) {
                FileMover.sessionTotals(rootURL: rootURL)
            }.value
            totals = computed
        }
    }

    private func moveFiles() {
        guard let folderURL = session.folderURL else { return }
        let items = session.items
        isMoving = true
        moveError = nil
        moveProgress = 0

        Task {
            let (stream, continuation) = AsyncStream<Double>.makeStream()
            let work = Task.detached(priority: .userInitiated) {
                defer { continuation.finish() }
                return try FileMover.moveFiles(items: items, folderURL: folderURL) { completed, total in
                    continuation.yield(total == 0 ? 1 : Double(completed) / Double(total))
                }
            }

            for await fraction in stream {
                moveProgress = fraction
            }

            do {
                let result = try await work.value
                session.deleteSessionFile()
                isMoving = false
                moveComplete = true
                resultMessage = Self.moveResultMessage(result, folderURL: folderURL)
            } catch {
                isMoving = false
                moveError = error.localizedDescription
            }
        }
    }

    private func moveAllFolders() {
        guard let rootURL else { return }
        session.flushSave()
        isMoving = true
        moveError = nil
        moveProgress = 0

        Task {
            let (stream, continuation) = AsyncStream<Double>.makeStream()
            let work = Task.detached(priority: .userInitiated) {
                defer { continuation.finish() }
                return try FileMover.moveAllSessions(rootURL: rootURL) { completed, total in
                    continuation.yield(total == 0 ? 1 : Double(completed) / Double(total))
                }
            }

            for await fraction in stream {
                moveProgress = fraction
            }

            do {
                let result = try await work.value
                // The current folder's file may already be gone if it was part
                // of the move. This drops any pending debounced save without
                // touching the file, so a folder the move skipped keeps its
                // saved state.
                session.discardPendingSave()
                isMoving = false
                moveComplete = true
                resultMessage = Self.treeMoveResultMessage(result)
            } catch {
                isMoving = false
                moveError = error.localizedDescription
            }
        }
    }

    static func undecidedMessage(
        count: Int, folderURL: URL?,
        bundle: Bundle = Localization.bundle, locale: Locale = .current
    ) -> String {
        if let folderURL, let sortedFolder = SortedFolder(folderURL: folderURL) {
            let parent = sortedFolder.parentURL.lastPathComponent
            return String(localized: "\(count) undecided photos will move back to \(parent)/", bundle: bundle, locale: locale)
        }
        return String(localized: "\(count) photos are undecided. They will stay in place.", bundle: bundle, locale: locale)
    }

    static func moveResultMessage(
        _ result: MoveResult, folderURL: URL,
        bundle: Bundle = Localization.bundle, locale: Locale = .current
    ) -> String {
        if let sortedFolder = SortedFolder(folderURL: folderURL) {
            let moved = sortedFolder.decision == .pick ? result.rejects : result.picks
            let destination = sortedFolder.siblingURL.lastPathComponent
            let parent = sortedFolder.parentURL.lastPathComponent
            return String(localized: "\(moved) moved to \(destination)/, \(result.returnedToParent) moved back to \(parent)/", bundle: bundle, locale: locale)
        }
        let picks = StatusBar.countLabel(result.picks, kind: .picks, bundle: bundle, locale: locale)
        let rejects = StatusBar.countLabel(result.rejects, kind: .rejects, bundle: bundle, locale: locale)
        return String(localized: "\(picks) moved to Picks/, \(rejects) moved to Rejects/", bundle: bundle, locale: locale)
    }

    static func treeMoveResultMessage(
        _ result: TreeMoveResult,
        bundle: Bundle = Localization.bundle, locale: Locale = .current
    ) -> String {
        let picks = StatusBar.countLabel(result.picks, kind: .picks, bundle: bundle, locale: locale)
        let rejects = StatusBar.countLabel(result.rejects, kind: .rejects, bundle: bundle, locale: locale)
        if result.returnedToParent > 0 {
            let returned = StatusBar.countLabel(result.returnedToParent, kind: .photos, bundle: bundle, locale: locale)
            return String(localized: "Moved across \(result.folders) folders: \(picks), \(rejects), \(returned) returned to parent folders", bundle: bundle, locale: locale)
        }
        return String(localized: "Moved across \(result.folders) folders: \(picks), \(rejects)", bundle: bundle, locale: locale)
    }
}

struct SummaryRow: View {
    let label: String
    let count: Int
    let color: Color
    let icon: String

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(color)
            Spacer()
            Text("\(count)")
                .monospacedDigit()
                .fontWeight(.semibold)
        }
        .font(.title3)
    }
}
