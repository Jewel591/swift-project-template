import SwiftUI

struct ThumbnailView: View {
    let assetID: String
    let thumbnailURL: URL
    let aspectRatio: CGFloat

    @State private var image: UIImage?
    @Environment(\.thumbnailLoader) private var loader

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.Background.card)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .task(id: assetID) {
            image = await loader.loadThumbnail(
                assetID: assetID,
                thumbnailURL: thumbnailURL,
                targetSize: CGSize(width: 200, height: 200)
            )
        }
    }
}

// Environment key for ThumbnailLoader
private struct ThumbnailLoaderKey: EnvironmentKey {
    static let defaultValue = ThumbnailLoader()
}

extension EnvironmentValues {
    var thumbnailLoader: ThumbnailLoader {
        get { self[ThumbnailLoaderKey.self] }
        set { self[ThumbnailLoaderKey.self] = newValue }
    }
}
