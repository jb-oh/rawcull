import SwiftUI

struct StatusBar: View {
    let currentIndex: Int
    let totalCount: Int
    let decision: Decision
    let pickCount: Int
    let rejectCount: Int

    var body: some View {
        HStack(spacing: 16) {
            // Navigation counter
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                Text("\(currentIndex + 1) / \(totalCount)")
                    .monospacedDigit()
                    .fontWeight(.medium)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }

            Divider()
                .frame(height: 16)

            // Decision badge
            HStack(spacing: 4) {
                Circle()
                    .fill(decisionColor)
                    .frame(width: 8, height: 8)
                Text(decisionLabel)
                    .font(.callout)
                    .foregroundStyle(decisionColor)
            }

            Spacer()

            // Counts
            HStack(spacing: 12) {
                Label("\(pickCount)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("\(rejectCount)", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
            .font(.callout)
            .monospacedDigit()

            Divider()
                .frame(height: 16)

            // Keyboard hints
            Text("A accept  S unmark  D reject  Z/X/C view  Space zoom")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var decisionColor: Color {
        switch decision {
        case .undecided: return .secondary
        case .pick: return .green
        case .reject: return .red
        }
    }

    private var decisionLabel: String {
        switch decision {
        case .undecided: return "Undecided"
        case .pick: return "Pick"
        case .reject: return "Reject"
        }
    }
}
