import SwiftUI

struct AssetDetailSheet: View {
    let asset: Asset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("File Info") {
                    row("Name", asset.name)
                    row("Format", asset.fileExtension.uppercased())
                    row("Size", ByteCountFormatter.string(
                        fromByteCount: asset.fileSize, countStyle: .file))
                    row("Dimensions", "\(asset.width) x \(asset.height)")
                }

                if asset.rating > 0 {
                    Section("Rating") {
                        HStack {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= asset.rating ? "star.fill" : "star")
                                    .foregroundStyle(star <= asset.rating ? .yellow : Color.Text.quaternary)
                            }
                        }
                    }
                }

                if let annotation = asset.annotation, !annotation.isEmpty {
                    Section("Notes") {
                        Text(annotation)
                            .foregroundStyle(Color.Text.primary)
                    }
                }

                if let url = asset.sourceURL, !url.isEmpty {
                    Section("Source") {
                        Text(url)
                            .foregroundStyle(.blue)
                            .lineLimit(2)
                    }
                }

                Section("Dates") {
                    row("Created", asset.createdAt.formatted())
                    row("Modified", asset.modifiedAt.formatted())
                    row("Imported", asset.importedAt.formatted())
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.Text.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(Color.Text.primary)
        }
    }
}
