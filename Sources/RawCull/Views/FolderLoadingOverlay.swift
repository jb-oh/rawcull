import FavrenUI
import SwiftUI

/// State of an in-flight folder switch, handed from ContentView to CullingView.
struct FolderLoading: Equatable {
    let folderName: String
    let foundCount: Int
    /// False during the short grace period before the overlay appears, so
    /// fast switches of small folders do not flash.
    let showsOverlay: Bool
}

struct FolderLoadingOverlay: View {
    let folderName: String
    let foundCount: Int

    var body: some View {
        ZStack {
            FavrenColors.brand.graphite
                .opacity(0.6)

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(FavrenColors.brand.bone)

                Text("Loading \(folderName)…")
                    .font(.headline)
                    .foregroundStyle(FavrenColors.brand.bone)

                if foundCount > 0 {
                    Text("\(foundCount.formatted()) found")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(FavrenColors.brand.bone.opacity(0.7))
                }
            }
            .padding(24)
        }
    }
}
