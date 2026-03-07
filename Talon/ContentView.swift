import SwiftUI

struct ContentView: View {
    @State private var database: AppDatabase?
    @State private var libraryURL: URL?
    @State private var showFilePicker = false
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if let database, let libraryURL {
                mainTabView(database: database, libraryURL: libraryURL)
            } else {
                welcomeView
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderSelection(result)
        }
    }

    private func mainTabView(database: AppDatabase, libraryURL: URL) -> some View {
        TabView(selection: $selectedTab) {
            Tab("Browse", systemImage: "photo.on.rectangle.angled", value: 0) {
                LibraryBrowserView(
                    database: database,
                    libraryURL: libraryURL
                )
            }

            Tab("Search", systemImage: "magnifyingglass", value: 1) {
                SearchView(
                    database: database,
                    libraryURL: libraryURL
                )
            }

            Tab("Settings", systemImage: "gearshape", value: 2) {
                SettingsView()
            }
        }
    }

    private var welcomeView: some View {
        VStack(spacing: BrandSpacing.cardContent) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(Color.Text.tertiary)

            Text("Open Eagle Library")
                .font(.title2)
                .foregroundStyle(Color.Text.primary)

            Text("Select your .library folder to get started")
                .font(.body)
                .foregroundStyle(Color.Text.secondary)

            Button {
                showFilePicker = true
            } label: {
                Text("Choose Library")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        guard let url = try? result.get().first else { return }

        // Save security-scoped bookmark
        let accessManager = ScopedAccessManager()
        Task {
            try? await accessManager.saveBookmark(for: url)
            UserDefaults.standard.set(url.path, forKey: "lastLibraryPath")

            // Open database
            let dbPath = url
                .appendingPathComponent(".talon_index.sqlite")
                .path
            let db = try AppDatabase.openLibrary(at: dbPath)
            self.database = db
            self.libraryURL = url

            // Start indexing
            let indexer = LibraryIndexer(database: db)
            try await indexer.indexLibrary(libraryURL: url) { _, _ in }
        }
    }
}

#Preview {
    ContentView()
}
