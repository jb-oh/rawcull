import AppKit
import FavrenUI
import SwiftUI

struct ThumbnailSidebar: View {
    @Environment(CullSession.self) private var session
    @Environment(ImageLoader.self) private var imageLoader
    var imageHeight: CGFloat = 75
    var previewRotation: (URL) -> Int = { _ in 0 }
    var onRotate: (Int, [PhotoItem]) -> Void = { _, _ in }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    ForEach(session.items.indices, id: \.self) { index in
                        let item = session.items[index]
                        ThumbnailCell(
                            image: imageLoader.thumbnail(for: item.url),
                            filename: item.filename,
                            decision: item.decision,
                            isCurrent: index == session.currentIndex,
                            isSelected: session.isSelected(index: index),
                            imageHeight: imageHeight,
                            rotationQuarterTurns: session.selectionCount > 1 && session.isSelected(index: index)
                                ? previewRotation(item.url) : 0
                        )
                        .id(item.id)
                        .task(id: item.url) {
                            imageLoader.loadThumbnailIfNeeded(for: item.url)
                        }
                        .onTapGesture {
                            Self.select(index: index, modifiers: Self.selectionModifiers(), in: session)
                        }
                        .contextMenu {
                            // Resolve once when SwiftUI builds the menu on opening.
                            let targets = session.contextMenuTargets(index: index)
                            ForEach([Decision.pick, .reject, .undecided], id: \.self) { decision in
                                Button(Self.decisionTitle(decision, count: targets.count)) {
                                    session.applyDecision(decision, to: targets.map(\.id))
                                }
                            }
                            Divider()
                            Button("Rotate Left") { onRotate(-1, targets) }
                            Button("Rotate Right") { onRotate(1, targets) }
                            Divider()
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.url))
                            }
                        }
                    }
                }
                .padding(4)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .onChange(of: session.currentIndex) { _, _ in
                scrollToCurrent(proxy: proxy)
            }
            .onChange(of: imageHeight) { _, _ in
                scrollToCurrent(proxy: proxy)
            }
            .onAppear {
                scrollToCurrent(proxy: proxy)
            }
        }
    }

    private func scrollToCurrent(proxy: ScrollViewProxy) {
        guard let item = session.currentItem else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(item.id, anchor: .center)
        }
    }

    static func selectionModifiers(
        for event: NSEvent? = NSApp.currentEvent,
        fallback: @autoclosure () -> NSEvent.ModifierFlags = NSEvent.modifierFlags
    ) -> NSEvent.ModifierFlags {
        event?.modifierFlags ?? fallback()
    }

    static func select(index: Int, modifiers: NSEvent.ModifierFlags, in session: CullSession) {
        guard !modifiers.contains(.control) else { return }
        session.select(
            index: index,
            extendingRange: modifiers.contains(.shift),
            toggling: modifiers.contains(.command)
        )
    }

    static func decisionTitle(
        _ decision: Decision, count: Int,
        bundle: Bundle = Localization.bundle, locale: Locale = .current
    ) -> String {
        if count > 1 {
            switch decision {
            case .pick: return String(localized: "Pick \(count) Photos", bundle: bundle, locale: locale)
            case .reject: return String(localized: "Reject \(count) Photos", bundle: bundle, locale: locale)
            case .undecided: return String(localized: "Unmark \(count) Photos", bundle: bundle, locale: locale)
            }
        }
        switch decision {
        case .pick: return String(localized: "Pick", bundle: bundle, locale: locale)
        case .reject: return String(localized: "Reject", bundle: bundle, locale: locale)
        case .undecided: return String(localized: "Unmark", bundle: bundle, locale: locale)
        }
    }
}

struct ThumbnailCell: View {
    let image: NSImage?
    let filename: String
    let decision: Decision
    let isCurrent: Bool
    let isSelected: Bool
    var imageHeight: CGFloat = 75
    var rotationQuarterTurns = 0

    var body: some View {
        VStack(spacing: 4) {
            thumbnail

            Text(verbatim: filename)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isCurrent ? FavrenColors.onSurface : FavrenColors.onSurfaceVariant)
                .frame(maxWidth: .infinity)
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(FavrenColors.primary.opacity(isCurrent ? 0.25 : isSelected ? 0.15 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    FavrenColors.primary.opacity(isCurrent ? 1 : isSelected ? 0.7 : 0),
                    lineWidth: 2
                )
        }
        .contentShape(Rectangle())
        .help(Text(verbatim: filename))
    }

    private var thumbnail: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnail image
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .rotationEffect(.degrees(Double(rotationQuarterTurns) * 90))
                } else {
                    Rectangle()
                        .fill(FavrenColors.surfaceVariant)
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                }
            }
            .frame(height: imageHeight)
            .clipped()

            // Decision dot
            if decision != .undecided {
                Circle()
                    .fill(decision == .pick ? FavrenSemantic.success : FavrenSemantic.danger)
                    .frame(width: 10, height: 10)
                    .padding(4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .opacity(decision == .reject ? 0.5 : 1.0)
    }
}
