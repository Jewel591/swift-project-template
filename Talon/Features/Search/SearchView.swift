import SwiftUI

struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    let database: AppDatabase
    let libraryURL: URL

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.results.isEmpty && viewModel.searchText.isEmpty {
                    historySection
                } else {
                    resultsSection
                }
            }
            .navigationTitle("Search")
            .searchable(text: $viewModel.searchText, prompt: "Search assets...")
            .onChange(of: viewModel.searchText) {
                let coordinator = SearchCoordinator(database: database)
                viewModel.performSearch(coordinator: coordinator)
            }
        }
    }

    private var historySection: some View {
        List {
            if !viewModel.searchHistory.isEmpty {
                Section("Recent") {
                    ForEach(viewModel.searchHistory, id: \.self) { query in
                        Button {
                            viewModel.searchText = query
                        } label: {
                            Label(query, systemImage: "clock")
                                .foregroundStyle(Color.Text.primary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var resultsSection: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100), spacing: BrandSpacing.compact)],
                spacing: BrandSpacing.compact
            ) {
                ForEach(viewModel.results) { asset in
                    let url = libraryURL
                        .appendingPathComponent("images")
                        .appendingPathComponent(asset.relativePath)
                        .appendingPathComponent("_thumbnail.png")
                    ThumbnailView(
                        assetID: asset.id,
                        thumbnailURL: url,
                        aspectRatio: CGFloat(asset.width) / max(CGFloat(asset.height), 1)
                    )
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
                }
            }
            .padding(.horizontal, BrandSpacing.pageHorizontal)
        }
    }
}
