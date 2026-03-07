import SwiftUI

struct SettingsView: View {
    @State private var cacheSize: String = "Calculating..."
    @State private var libraryPath: String = UserDefaults.standard.string(forKey: "lastLibraryPath") ?? "Not set"
    @State private var showClearConfirm = false

    private let diskCache = DiskCacheManager()

    var body: some View {
        NavigationStack {
            List {
                librarySection
                cacheSection
                aboutSection
            }
            .navigationTitle("Settings")
            .task {
                await calculateCacheSize()
            }
            .alert("Clear Cache", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    Task {
                        try? await diskCache.clearAll()
                        await calculateCacheSize()
                    }
                }
            } message: {
                Text("This will remove all cached thumbnails. They will be re-cached when viewed.")
            }
        }
    }

    private var librarySection: some View {
        Section("Library") {
            HStack {
                Text("Location")
                    .foregroundStyle(Color.Text.secondary)
                Spacer()
                Text(libraryPath)
                    .foregroundStyle(Color.Text.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var cacheSection: some View {
        Section("Cache") {
            HStack {
                Text("Thumbnail Cache")
                    .foregroundStyle(Color.Text.secondary)
                Spacer()
                Text(cacheSize)
                    .foregroundStyle(Color.Text.primary)
            }

            Button("Clear Cache", role: .destructive) {
                showClearConfirm = true
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                    .foregroundStyle(Color.Text.secondary)
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(Color.Text.primary)
            }
        }
    }

    private func calculateCacheSize() async {
        if let size = try? await diskCache.currentCacheSize() {
            cacheSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        } else {
            cacheSize = "Unknown"
        }
    }
}
