import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ImportPhotosTabView: View {
    @ObservedObject var viewModel: PhotogrammetryViewModel

    private let supportedContentTypes: [UTType] = [
        .jpeg,
        .png,
        .heic,
        .tiff,
        .image,
    ]

    var body: some View {
        VStack(spacing: 10) {
            importSection
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fileImporter(
            isPresented: $viewModel.isImportPickerPresented,
            allowedContentTypes: supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                viewModel.handleImportedImageURLs(urls, behavior: .append)
            case .failure(let error):
                viewModel.handleImportFailure(error)
            }
        }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            dropZoneContainer
                .frame(maxHeight: .infinity)

            if !viewModel.droppedImageURLs.isEmpty {
                HStack(spacing: 8) {
                    Button {
                        viewModel.clearSelection()
                    } label: {
                        Label("Clear all", systemImage: "xmark")
                    }
                    .disabled(!viewModel.canClearSelection)
                    .help("Remove all selected photos from the list.")
                }
            }
        }
        .accessibilityLabel("Import Area")
        .accessibilityHint("Drag and drop images here, or click to open the file picker")
    }

    @ViewBuilder
    private var dropZone: some View {
        if viewModel.droppedImageURLs.isEmpty {
            VStack(spacing: 8) {
                Text("Drag and drop images here or click")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { proxy in
                let spacing: CGFloat = 10
                let minItemWidth: CGFloat = 120
                let columnCount = max(Int((proxy.size.width + spacing) / (minItemWidth + spacing)), 1)
                let columns = Array(
                    repeating: GridItem(.flexible(minimum: minItemWidth), spacing: spacing, alignment: .top),
                    count: columnCount
                )

                ScrollView {
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(viewModel.droppedImageURLs, id: \.self) { imageURL in
                            ThumbnailView(
                                imageURL: imageURL,
                                canRemove: viewModel.canImportImages,
                                onRemove: { viewModel.removeImage(imageURL) }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
        }
    }

    private var dropZoneContainer: some View {
        dropZone
            .frame(maxWidth: .infinity, minHeight: 130, maxHeight: .infinity)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(viewModel.isDropTargeted ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(viewModel.isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.presentImportPicker()
            }
            .help("Click to import photos, or drag and drop files here.")
            .dropDestination(for: URL.self) { urls, _ in
                viewModel.handleImportedImageURLs(urls, behavior: .replace)
                return true
            } isTargeted: { targeted in
                viewModel.isDropTargeted = targeted
            }
    }
}

private struct ThumbnailView: View {
    let imageURL: URL
    let canRemove: Bool
    let onRemove: () -> Void

    @State private var image: NSImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .overlay {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("Remove this photo from the selection.")
            .disabled(!canRemove)
        }
        .task(id: imageURL, priority: .utility) {
            await loadThumbnailIfNeeded()
        }
        .accessibilityLabel(imageURL.lastPathComponent)
    }

    @MainActor
    private func loadThumbnailIfNeeded() async {
        guard image == nil, !isLoading else { return }
        isLoading = true

        let loaded = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.makeThumbnail(from: imageURL, maxPixelSize: 600))
            }
        }

        if !Task.isCancelled {
            image = loaded
        }

        isLoading = false
    }

    nonisolated private static func makeThumbnail(from url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
