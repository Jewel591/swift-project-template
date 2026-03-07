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

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            if let image = UIImage(contentsOfFile: url.path) ?? UIImage(contentsOfFile: fallbackURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = lastScale * value.magnification
                            }
                            .onEnded { value in
                                lastScale = max(1.0, min(scale, 5.0))
                                scale = lastScale
                                if lastScale == 1.0 {
                                    withAnimation(.spring(duration: 0.3)) {
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1.0 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(duration: 0.3)) {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 3.0
                                lastScale = 3.0
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                ContentUnavailableView("Cannot load image", systemImage: "photo")
            }
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
