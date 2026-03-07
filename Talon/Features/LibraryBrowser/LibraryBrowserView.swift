import SwiftUI

struct LibraryBrowserView: View {
    @State private var browserVM = LibraryBrowserViewModel()
    @State private var gridVM = AssetGridViewModel()
    @State private var selectedAsset: Asset?
    let database: AppDatabase
    let libraryURL: URL

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !browserVM.breadcrumbs.isEmpty {
                    breadcrumbBar
                }
                if !folderList.isEmpty {
                    folderSection
                }
                AssetGridView(
                    viewModel: gridVM,
                    database: database,
                    libraryURL: libraryURL,
                    onAssetTap: { selectedAsset = $0 }
                )
            }
            .navigationTitle(browserVM.currentFolder?.name ?? "Library")
            .task {
                browserVM.database = database
                browserVM.libraryURL = libraryURL
                gridVM.observe(database: database, folderID: browserVM.currentFolder?.id)
                await browserVM.loadRootFolders()
            }
            .overlay {
                if browserVM.isIndexing {
                    indexingOverlay
                }
            }
        }
    }

    private var folderList: [Folder] {
        browserVM.currentFolder == nil ? browserVM.rootFolders : browserVM.childFolders
    }

    private var folderSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.compact) {
                ForEach(folderList) { folder in
                    Button {
                        Task {
                            await browserVM.navigateToFolder(folder)
                            gridVM.observe(database: database, folderID: folder.id)
                        }
                    } label: {
                        Label(folder.name, systemImage: "folder")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.Background.card)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.pageHorizontal)
            .padding(.vertical, BrandSpacing.compact)
        }
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button("Root") {
                    Task {
                        await browserVM.navigateToRoot()
                        gridVM.observe(database: database)
                    }
                }
                ForEach(browserVM.breadcrumbs) { folder in
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.Text.tertiary)
                    Button(folder.name) {}
                }
            }
            .font(.caption)
            .foregroundStyle(Color.Text.secondary)
            .padding(.horizontal, BrandSpacing.pageHorizontal)
            .padding(.vertical, 4)
        }
    }

    private var indexingOverlay: some View {
        VStack(spacing: BrandSpacing.cardContent) {
            ProgressView(
                value: Double(browserVM.indexingProgress.current),
                total: Double(max(browserVM.indexingProgress.total, 1))
            )
            Text("Indexing \(browserVM.indexingProgress.current)/\(browserVM.indexingProgress.total)")
                .font(.caption)
                .foregroundStyle(Color.Text.secondary)
        }
        .padding(BrandSpacing.cardPadding)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
