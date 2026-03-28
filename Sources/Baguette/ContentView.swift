import AppKit
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
                                    thumbnailView(for: imageURL)
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
    private func thumbnailView(for imageURL: URL) -> some View {
        if let image = NSImage(contentsOf: imageURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
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
