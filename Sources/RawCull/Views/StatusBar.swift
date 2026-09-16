import FavrenUI
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
                Text(totalCount == 0 ? "0 / 0" : "\(currentIndex + 1) / \(totalCount)")
                    .monospacedDigit()
                    .fontWeight(.medium)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }

            Divider()
                .frame(height: 16)

            // Decision badge
            FavrenBadge(decisionLabel, tone: decisionTone)

            Spacer()

            // Counts
            HStack(spacing: 12) {
                Label("\(pickCount)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(FavrenSemantic.success)
                Label("\(rejectCount)", systemImage: "xmark.circle.fill")
                    .foregroundStyle(FavrenSemantic.danger)
            }
            .font(.callout)
            .monospacedDigit()

            Divider()
                .frame(height: 16)

            // Keyboard hints
            HStack(spacing: 6) {
                FavrenKeyCap("A")
                Text("accept")
                FavrenKeyCap("S")
                Text("unmark")
                FavrenKeyCap("D")
                Text("reject")
                FavrenKeyCap("Z")
                FavrenKeyCap("X")
                FavrenKeyCap("C")
                Text("view")
                FavrenKeyCap("Space")
                Text("zoom")
            }
            .font(.caption)
            .foregroundStyle(FavrenColors.onSurfaceVariant)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var decisionTone: FavrenBadge.Tone {
        switch decision {
        case .undecided: return .neutral
        case .pick: return .success
        case .reject: return .danger
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
