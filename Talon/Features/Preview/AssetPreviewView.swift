import SwiftUI
import PDFKit
import WebKit

struct AssetPreviewView: View {
    let asset: Asset
    let libraryURL: URL
    @State private var showDetail = false

    private var fileURL: URL {
        libraryURL
            .appendingPathComponent("images")
            .appendingPathComponent(asset.relativePath)
            .appendingPathComponent("\(asset.name).\(asset.fileExtension)")
    }

    private var thumbnailURL: URL {
        libraryURL
            .appendingPathComponent("images")
            .appendingPathComponent(asset.relativePath)
            .appendingPathComponent("_thumbnail.png")
    }

    var body: some View {
        NavigationStack {
            previewContent
                .navigationTitle(asset.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Info") { showDetail = true }
                    }
                }
                .sheet(isPresented: $showDetail) {
                    AssetDetailSheet(asset: asset)
                }
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch asset.fileExtension.lowercased() {
        case "jpg", "jpeg", "png", "webp", "heic", "bmp", "tiff":
            imagePreview
        case "gif":
            imagePreview
        case "svg":
            svgPreview
        case "pdf":
            pdfPreview
        default:
            fallbackPreview
        }
    }

    private var imagePreview: some View {
        ZoomableImageView(url: fileURL, fallbackURL: thumbnailURL)
    }

    private var svgPreview: some View {
        SVGWebView(url: fileURL)
    }

    private var pdfPreview: some View {
        PDFPreviewView(url: fileURL)
    }

    private var fallbackPreview: some View {
        VStack(spacing: BrandSpacing.cardContent) {
            ZoomableImageView(url: thumbnailURL, fallbackURL: thumbnailURL)
            Text(asset.fileExtension.uppercased())
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.Background.card)
                .clipShape(Capsule())
                .foregroundStyle(Color.Text.secondary)
        }
    }
}

struct ZoomableImageView: View {
    let url: URL
    let fallbackURL: URL

    var body: some View {
        if let image = UIImage(contentsOfFile: url.path) ?? UIImage(contentsOfFile: fallbackURL.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            ContentUnavailableView("Cannot load image", systemImage: "photo")
        }
    }
}

struct SVGWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

struct PDFPreviewView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {}
}
