import SwiftUI

struct SummaryView: View {
    @Environment(CullSession.self) private var session
    let onGoBack: () -> Void
    let onComplete: () -> Void

    @State private var isMoving = false
    @State private var moveProgress = 0.0
    @State private var moveError: String?
    @State private var moveComplete = false
    @State private var resultMessage = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(moveComplete ? .green : .secondary)

            Text(moveComplete ? "Done!" : "Culling Summary")
                .font(.largeTitle.bold())

            if moveComplete {
                Text(resultMessage)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Button("Back to Start") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                // Stats
                VStack(spacing: 12) {
                    SummaryRow(label: "Picks", count: session.pickCount, color: .green, icon: "checkmark.circle.fill")
                    SummaryRow(label: "Rejects", count: session.rejectCount, color: .red, icon: "xmark.circle.fill")
                    SummaryRow(label: "Undecided", count: session.undecidedCount, color: .secondary, icon: "questionmark.circle")
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary))

                if session.undecidedCount > 0 {
                    Label(
                        "\(session.undecidedCount) photos are undecided — they will stay in place",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    .font(.callout)
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
                        .controlSize(.large)

                        Button("Move Files") {
                            moveFiles()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(session.pickCount + session.rejectCount == 0)
                    }
                }

                if let error = moveError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func moveFiles() {
        guard let folderURL = session.folderURL else { return }
        isMoving = true
        moveError = nil

        Task {
            do {
                let result = try FileMover.moveFiles(
                    items: session.items,
                    folderURL: folderURL
                ) { completed, total in
                    Task { @MainActor in
                        moveProgress = Double(completed) / Double(total)
                    }
                }

                session.deleteSessionFile()

                await MainActor.run {
                    isMoving = false
                    moveComplete = true
                    resultMessage = "\(result.picks) picks moved to Picks/, \(result.rejects) rejects moved to Rejects/"
                }
            } catch {
                await MainActor.run {
                    isMoving = false
                    moveError = error.localizedDescription
                }
            }
        }
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
