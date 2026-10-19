import FavrenUI
import SwiftUI

struct StatusBar: View {
    @Environment(KeyBindingStore.self) private var shortcuts
    let currentIndex: Int
    let totalCount: Int
    let decision: Decision
    let pickCount: Int
    let rejectCount: Int
    let undecidedCount: Int
    let selectionCount: Int

    var body: some View {
        StatusBarFlowLayout {
            position
                .fixedSize()

            Text(Self.countLabel(totalCount, kind: .photos))
                .font(.callout)
                .monospacedDigit()
                .fixedSize()
            Label(Self.countLabel(pickCount, kind: .picks), systemImage: "checkmark.circle.fill")
                .foregroundStyle(FavrenSemantic.success)
                .font(.callout)
                .monospacedDigit()
                .fixedSize()
            Label(Self.countLabel(rejectCount, kind: .rejects), systemImage: "xmark.circle.fill")
                .foregroundStyle(FavrenSemantic.danger)
                .font(.callout)
                .monospacedDigit()
                .fixedSize()
            Text("\(undecidedCount) left")
                .foregroundStyle(.secondary)
                .font(.callout)
                .monospacedDigit()
                .fixedSize()

            if selectionCount > 1 {
                Text(Self.selectionLabel(selectionCount))
                    .foregroundStyle(FavrenColors.primary)
                    .font(.callout)
                    .monospacedDigit()
                    .fixedSize()
            }

            hint([.pick], String(localized: "accept", bundle: Localization.bundle))
            hint([.unmark], String(localized: "unmark", bundle: Localization.bundle))
            hint([.reject], String(localized: "reject", bundle: Localization.bundle))
            rotationHint
            hint([.saveRotation], String(localized: "save rotation", bundle: Localization.bundle))
            hint([.zoom], String(localized: "zoom", bundle: Localization.bundle))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var position: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left")
                .foregroundStyle(.tertiary)
                .font(.caption)
            Text("\(totalCount == 0 ? 0 : currentIndex + 1) / \(totalCount)")
                .monospacedDigit()
                .fontWeight(.medium)
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .font(.caption)
            Divider()
                .frame(height: 16)
            FavrenBadge(decisionLabel, tone: decisionTone)
        }
    }

    @ViewBuilder
    private func hint(_ actions: [CullAction], _ label: String) -> some View {
        let keys = actions.compactMap { shortcuts.keys(for: $0).first }
        if !keys.isEmpty {
            HStack(spacing: 6) {
                ForEach(keys) { key in
                    FavrenKeyCap(key.label)
                }
                Text(label)
            }
            .font(.caption)
            .foregroundStyle(FavrenColors.onSurfaceVariant)
            .fixedSize()
            .layoutValue(key: StatusBarHintKey.self, value: true)
        }
    }

    /// Z and C show their rotation direction as an icon, X says it returns to the original view.
    @ViewBuilder
    private var rotationHint: some View {
        let parts = [CullAction.rotateCounterClockwise, .resetView, .rotateClockwise].compactMap { action in
            shortcuts.keys(for: action).first.map { (action: action, key: $0) }
        }
        if !parts.isEmpty {
            HStack(spacing: 10) {
                ForEach(parts, id: \.action) { part in
                    HStack(spacing: 4) {
                        FavrenKeyCap(part.key.label)
                        switch part.action {
                        case .rotateCounterClockwise: Image(systemName: "rotate.left")
                        case .rotateClockwise: Image(systemName: "rotate.right")
                        default: Text(String(localized: "reset", bundle: Localization.bundle))
                        }
                    }
                    .help(part.action.displayName)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(part.action.displayName)
                }
            }
            .font(.caption)
            .foregroundStyle(FavrenColors.onSurfaceVariant)
            .fixedSize()
            .layoutValue(key: StatusBarHintKey.self, value: true)
        }
    }

    enum CountKind: CaseIterable {
        case photos, picks, rejects
    }

    static func selectionLabel(
        _ count: Int, bundle: Bundle = Localization.bundle, locale: Locale = .current
    ) -> String {
        String(localized: "\(count) selected", bundle: bundle, locale: locale)
    }

    static func countLabel(
        _ count: Int, kind: CountKind,
        bundle: Bundle = Localization.bundle, locale: Locale = .current
    ) -> String {
        switch kind {
        case .photos: return String(localized: "\(count) photos", bundle: bundle, locale: locale)
        case .picks: return String(localized: "\(count) picks", bundle: bundle, locale: locale)
        case .rejects: return String(localized: "\(count) rejects", bundle: bundle, locale: locale)
        }
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
        case .undecided: return String(localized: "Undecided", bundle: Localization.bundle)
        case .pick: return String(localized: "Pick", bundle: Localization.bundle)
        case .reject: return String(localized: "Reject", bundle: Localization.bundle)
        }
    }
}

private struct StatusBarHintKey: LayoutValueKey {
    static let defaultValue = false
}

struct StatusBarFlowLayout: Layout {
    var spacing: CGFloat = 16
    var lineSpacing: CGFloat = 8

    struct Arrangement {
        let size: CGSize
        let frames: [CGRect]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(
            sizes: subviews.map { $0.sizeThatFits(.unspecified) },
            width: proposal.width,
            firstHintIndex: subviews.firstIndex { $0[StatusBarHintKey.self] }
        ).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(
            sizes: subviews.map { $0.sizeThatFits(.unspecified) },
            width: bounds.width,
            firstHintIndex: subviews.firstIndex { $0[StatusBarHintKey.self] }
        )
        for (subview, frame) in zip(subviews, result.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    /// Measures and places the same ideal-size units, keeping stats ahead of hints.
    func arrangement(sizes: [CGSize], width: CGFloat?, firstHintIndex: Int?) -> Arrangement {
        let idealWidth = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, sizes.count - 1))
        let availableWidth = max(
            width.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth,
            sizes.map(\.width).max() ?? 0
        )
        var rows: [[Int]] = []
        var rowWidth: CGFloat = 0
        for index in sizes.indices {
            if rows.isEmpty || rowWidth + spacing + sizes[index].width > availableWidth {
                rows.append([index])
                rowWidth = sizes[index].width
            } else {
                rows[rows.count - 1].append(index)
                rowWidth += spacing + sizes[index].width
            }
        }

        var frames: [CGRect] = []
        var y: CGFloat = 0
        for row in rows {
            let height = row.map { sizes[$0].height }.max() ?? 0
            var x: CGFloat = 0
            for index in row {
                // Only the single-line bar uses the spare width as a spacer before hints.
                if rows.count == 1, index == firstHintIndex {
                    x += availableWidth - idealWidth
                }
                frames.append(CGRect(
                    x: x, y: y + (height - sizes[index].height) / 2,
                    width: sizes[index].width, height: sizes[index].height
                ))
                x += sizes[index].width + spacing
            }
            y += height + lineSpacing
        }
        return Arrangement(
            size: CGSize(width: availableWidth, height: rows.isEmpty ? 0 : y - lineSpacing),
            frames: frames
        )
    }
}
