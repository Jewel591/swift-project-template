import SwiftUI

struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    @State private var showFilters = false
    let database: AppDatabase
    let libraryURL: URL

    private var hasActiveFilters: Bool {
        !viewModel.selectedTags.isEmpty || !viewModel.selectedFileTypes.isEmpty
            || viewModel.minRating > 0 || viewModel.dateFrom != nil || viewModel.dateTo != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showFilters {
                    filterPanel
                }
                if viewModel.results.isEmpty && viewModel.searchText.isEmpty && !hasActiveFilters {
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { showFilters.toggle() }
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    private var filterPanel: some View {
        VStack(spacing: BrandSpacing.compact) {
            // File type filter
            VStack(alignment: .leading, spacing: 4) {
                Text("File Type")
                    .font(.caption)
                    .foregroundStyle(Color.Text.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["jpg", "png", "svg", "gif", "psd", "ai", "pdf", "webp"], id: \.self) { ext in
                            FilterChip(
                                label: ext.uppercased(),
                                isSelected: viewModel.selectedFileTypes.contains(ext)
                            ) {
                                if viewModel.selectedFileTypes.contains(ext) {
                                    viewModel.selectedFileTypes.removeAll { $0 == ext }
                                } else {
                                    viewModel.selectedFileTypes.append(ext)
                                }
                                let coordinator = SearchCoordinator(database: database)
                                viewModel.performSearch(coordinator: coordinator)
                            }
                        }
                    }
                }
            }

            // Rating filter
            VStack(alignment: .leading, spacing: 4) {
                Text("Minimum Rating")
                    .font(.caption)
                    .foregroundStyle(Color.Text.secondary)
                HStack(spacing: 4) {
                    ForEach(0...5, id: \.self) { rating in
                        Button {
                            viewModel.minRating = rating
                            let coordinator = SearchCoordinator(database: database)
                            viewModel.performSearch(coordinator: coordinator)
                        } label: {
                            Image(systemName: rating == 0 ? "star.slash" : (rating <= viewModel.minRating ? "star.fill" : "star"))
                                .foregroundStyle(rating <= viewModel.minRating && rating > 0 ? .yellow : Color.Text.quaternary)
                        }
                    }
                    Spacer()
                }
            }

            // Clear filters button
            if hasActiveFilters {
                Button("Clear Filters") {
                    viewModel.clearFilters()
                    let coordinator = SearchCoordinator(database: database)
                    viewModel.performSearch(coordinator: coordinator)
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, BrandSpacing.pageHorizontal)
        .padding(.vertical, BrandSpacing.compact)
        .background(Color.Background.card)
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

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.Background.card)
                .foregroundStyle(isSelected ? .white : Color.Text.primary)
                .clipShape(Capsule())
        }
    }
}
