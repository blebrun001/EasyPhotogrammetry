import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var viewModel: PhotogrammetryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            dropZone

            HStack(spacing: 8) {
                Label(viewModel.compactImageCountText, systemImage: "photo.stack")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                qualityMenu
            }

            HStack(spacing: 8) {
                Button("Run") {
                    Task {
                        await viewModel.generateModel()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!viewModel.canGenerateModel)

                if case .completed(let url) = viewModel.state {
                    Button("Open") {
                        NSWorkspace.shared.open(url)
                    }
                    .controlSize(.small)
                }
            }

            statusSection

            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private var qualityMenu: some View {
        Picker("Quality", selection: $viewModel.selectedQuality) {
            ForEach(ModelQuality.allCases) { quality in
                Text(quality.shortLabel)
                    .tag(quality)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .disabled({
            if case .processing = viewModel.state {
                return true
            }
            return false
        }())
        .help("Quality")
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(viewModel.isDropTargeted ? Color.accentColor : Color.gray.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.04))
            )
            .frame(maxWidth: .infinity, minHeight: 168)
            .overlay {
                if viewModel.droppedImageURLs.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                        Text("Drop images")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 6)], spacing: 6) {
                                ForEach(viewModel.droppedImageURLs, id: \.self) { imageURL in
                                    ThumbnailView(imageURL: imageURL)
                                }
                            }
                        }

                        Text("Drop to replace")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }
            }
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $viewModel.isDropTargeted, perform: viewModel.handleDroppedItems)
    }

    @ViewBuilder
    private var statusSection: some View {
        switch viewModel.state {
        case .processing(let progress):
            HStack(spacing: 8) {
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                ProgressView(value: progress)
                    .controlSize(.small)
            }
        case .failed(let message):
            Text(message)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.red)
        case .completed(let url):
            Text("Done • \(url.lastPathComponent)")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.green)
        case .ready:
            Text("Ready")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .idle:
            Text("Drop to start")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ThumbnailView: View {
    let imageURL: URL

    @State private var image: NSImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
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
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: imageURL) {
            await loadThumbnailIfNeeded()
        }
    }

    @MainActor
    private func loadThumbnailIfNeeded() async {
        guard image == nil, !isLoading else { return }
        isLoading = true

        let loaded = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.makeThumbnail(from: imageURL, maxPixelSize: 144))
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
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
