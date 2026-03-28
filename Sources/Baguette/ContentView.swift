import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var viewModel: PhotogrammetryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Baguette Photogrammetry")
                .font(.title.bold())

            Text("Glissez-déposez vos photos, puis lancez la génération du modèle 3D.")
                .foregroundStyle(.secondary)

            dropZone

            Text(viewModel.imageCountText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text("Qualité 3D")
                    .font(.subheadline.weight(.semibold))

                Picker("Qualité 3D", selection: $viewModel.selectedQuality) {
                    ForEach(ModelQuality.allCases) { quality in
                        Text(quality.label)
                            .tag(quality)
                    }
                }
                .pickerStyle(.menu)
                .disabled({
                    if case .processing = viewModel.state {
                        return true
                    }
                    return false
                }())
            }

            statusSection

            HStack(spacing: 12) {
                Button("Créer le modèle 3D") {
                    Task {
                        await viewModel.generateModel()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canGenerateModel)

                if case .completed(let url) = viewModel.state {
                    Button("Ouvrir le fichier") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(viewModel.isDropTargeted ? Color.accentColor : Color.gray.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8]))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.08))
            )
            .frame(maxWidth: .infinity, minHeight: 220)
            .overlay {
                if viewModel.droppedImageURLs.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 36))
                        Text("Déposez des images ici")
                            .font(.headline)
                        Text("Formats supportés: \(SupportedImageFormat.userFacingList)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Images ajoutées")
                            .font(.headline)

                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                                ForEach(viewModel.droppedImageURLs, id: \.self) { imageURL in
                                    ThumbnailView(imageURL: imageURL)
                                }
                            }
                        }

                        Text("Déposez à nouveau des images pour remplacer la sélection.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                }
            }
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $viewModel.isDropTargeted, perform: viewModel.handleDroppedItems)
    }

    @ViewBuilder
    private var statusSection: some View {
        switch viewModel.state {
        case .processing(let progress):
            VStack(alignment: .leading, spacing: 8) {
                Text("Traitement en cours... \(Int(progress * 100))%")
                ProgressView(value: progress)
            }
        case .failed(let message):
            Text("Erreur: \(message)")
                .foregroundStyle(.red)
        case .completed(let url):
            Text("Terminé: \(url.lastPathComponent)")
                .foregroundStyle(.green)
        default:
            Text(viewModel.state.statusText)
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
        .frame(width: 72, height: 72)
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
