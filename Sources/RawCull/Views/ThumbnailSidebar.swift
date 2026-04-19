import SwiftUI

struct ThumbnailSidebar: View {
    @Environment(CullSession.self) private var session
    @Environment(ImageLoader.self) private var imageLoader

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    ForEach(session.items.indices, id: \.self) { index in
                        let item = session.items[index]
                        ThumbnailCell(
                            image: imageLoader.thumbnail(for: item.url),
                            decision: item.decision,
                            isCurrent: index == session.currentIndex
                        )
                        .id(item.id)
                        .task(id: item.url) {
                            imageLoader.loadThumbnailIfNeeded(for: item.url)
                        }
                        .onTapGesture {
                            session.jumpTo(index: index)
                        }
                    }
                }
                .padding(4)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .onChange(of: session.currentIndex) { _, _ in
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
}

struct ThumbnailCell: View {
    let image: NSImage?
    let decision: Decision
    let isCurrent: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnail image
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                }
            }
            .frame(height: 75)
            .clipped()

            // Decision dot
            if decision != .undecided {
                Circle()
                    .fill(decision == .pick ? .green : .red)
                    .frame(width: 10, height: 10)
                    .padding(4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isCurrent ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .opacity(decision == .reject ? 0.5 : 1.0)
    }
}
