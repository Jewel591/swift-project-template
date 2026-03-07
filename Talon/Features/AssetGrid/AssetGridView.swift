import SwiftUI

struct AssetGridView: View {
    @Bindable var viewModel: AssetGridViewModel
    let database: AppDatabase
    let libraryURL: URL
    let onAssetTap: (Asset) -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 100), spacing: BrandSpacing.compact)
    ]

    var body: some View {
        Group {
            switch viewModel.layoutMode {
            case .grid:
                gridLayout
            case .waterfall:
                waterfallLayout
            case .list:
                listLayout
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                layoutPicker
            }
        }
    }

    private var gridLayout: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: BrandSpacing.compact) {
                ForEach(viewModel.assets) { asset in
                    assetThumbnail(asset)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                        .onTapGesture { onAssetTap(asset) }
                        .onAppear { loadMoreIfNeeded(asset) }
                }
            }
            .padding(.horizontal, BrandSpacing.pageHorizontal)

            if viewModel.isLoading {
                ProgressView()
                    .padding()
            }
        }
    }

    private var waterfallLayout: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: BrandSpacing.compact)],
                spacing: BrandSpacing.compact
            ) {
                ForEach(viewModel.assets) { asset in
                    assetThumbnail(asset)
                        .aspectRatio(
                            CGFloat(asset.width) / max(CGFloat(asset.height), 1),
                            contentMode: .fit
                        )
                        .onTapGesture { onAssetTap(asset) }
                        .onAppear { loadMoreIfNeeded(asset) }
                }
            }
            .padding(.horizontal, BrandSpacing.pageHorizontal)

            if viewModel.isLoading {
                ProgressView()
                    .padding()
            }
        }
    }

    private var listLayout: some View {
        List(viewModel.assets) { asset in
            HStack(spacing: BrandSpacing.cardContent) {
                assetThumbnail(asset)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.name)
                        .font(.body)
                        .foregroundStyle(Color.Text.primary)
                        .lineLimit(1)
                    Text("\(asset.fileExtension.uppercased()) · \(formatFileSize(asset.fileSize))")
                        .font(.caption)
                        .foregroundStyle(Color.Text.secondary)
                }
            }
            .onTapGesture { onAssetTap(asset) }
            .onAppear { loadMoreIfNeeded(asset) }
        }
        .listStyle(.plain)
    }

    /// Trigger pagination when the last few items appear
    private func loadMoreIfNeeded(_ asset: Asset) {
        let thresholdIndex = max(viewModel.assets.count - 5, 0)
        guard let index = viewModel.assets.firstIndex(where: { $0.id == asset.id }),
              index >= thresholdIndex
        else { return }
        Task {
            await viewModel.loadNextPage(database: database)
        }
    }

    private func assetThumbnail(_ asset: Asset) -> some View {
        let url = libraryURL
            .appendingPathComponent("images")
            .appendingPathComponent(asset.relativePath)
            .appendingPathComponent("_thumbnail.png")
        return ThumbnailView(
            assetID: asset.id,
            thumbnailURL: url,
            aspectRatio: CGFloat(asset.width) / max(CGFloat(asset.height), 1)
        )
    }

    private var layoutPicker: some View {
        Menu {
            ForEach(LayoutMode.allCases, id: \.self) { mode in
                Button {
                    viewModel.layoutMode = mode
                } label: {
                    Label(mode.rawValue.capitalized, systemImage: layoutIcon(mode))
                }
            }
        } label: {
            Image(systemName: layoutIcon(viewModel.layoutMode))
        }
    }

    private func layoutIcon(_ mode: LayoutMode) -> String {
        switch mode {
        case .grid: "square.grid.2x2"
        case .waterfall: "rectangle.grid.1x2"
        case .list: "list.bullet"
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
