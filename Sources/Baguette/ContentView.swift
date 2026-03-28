import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var viewModel: PhotogrammetryViewModel

    private let supportedContentTypes: [UTType] = [
        .jpeg,
        .png,
        .heic,
        .tiff,
        .image
    ]

    var body: some View {
        Form {
            Section("Import") {
                importSection
            }

            Section("Configuration") {
                configurationSection
            }

            Section("Status") {
                statusSection
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .fileImporter(
            isPresented: $viewModel.isImportPickerPresented,
            allowedContentTypes: supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                viewModel.handleImportedImageURLs(urls, behavior: .append)
            case .failure(let error):
                viewModel.state = .failed(message: error.localizedDescription)
            }
        }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            dropZoneContainer

            if !viewModel.droppedImageURLs.isEmpty {
                HStack(spacing: 8) {
                    Button {
                        viewModel.clearSelection()
                    } label: {
                        Label("Clear", systemImage: "xmark")
                    }
                    .disabled(!viewModel.canClearSelection)
                    .help("Clear selected images")
                }
            }
        }
        .accessibilityLabel("Import Area")
        .accessibilityHint("Drag and drop images here, or click to open the file picker")
    }

    private var configurationSection: some View {
        LabeledContent("Quality") {
            Picker("Quality", selection: $viewModel.selectedQuality) {
                ForEach(ModelQuality.allCases) { quality in
                    Text(quality.label)
                        .tag(quality)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .disabled(!viewModel.canImportImages)
            .help("Choose generation quality")
        }
    }

    @ViewBuilder
    private var dropZone: some View {
        if viewModel.droppedImageURLs.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                        ForEach(viewModel.droppedImageURLs, id: \.self) { imageURL in
                            ThumbnailView(imageURL: imageURL)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 88, maxHeight: 220)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
        }
    }

    private var dropZoneContainer: some View {
        dropZone
            .frame(maxWidth: .infinity, minHeight: 130)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.presentImportPicker()
            }
            .help("Click to choose images, or drop files")
            .dropDestination(for: URL.self) { urls, _ in
                viewModel.handleImportedImageURLs(urls, behavior: .replace)
                return true
            } isTargeted: { targeted in
                viewModel.isDropTargeted = targeted
            }
    }

    private var statusSection: some View {
        let presentation = viewModel.state.presentation

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: presentation.symbolName)
                    .foregroundStyle(color(for: presentation.tone))

                Text(presentation.title)
                    .font(.headline)
            }

            if let detail = presentation.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let progress = presentation.progress {
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .controlSize(.small)

                    if let progressText = presentation.progressText {
                        Text(progressText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                if viewModel.canCancelGeneration {
                    Button(role: .destructive) {
                        viewModel.cancelGeneration()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .keyboardShortcut(.cancelAction)
                    .help("Stop model generation")
                    .accessibilityLabel("Stop Generation")
                    .accessibilityHint("Cancel the 3D model generation in progress")
                } else {
                    Button {
                        viewModel.generateModel()
                    } label: {
                        Label("Generate", systemImage: "sparkles")
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canGenerateModel)
                    .help("Generate a USDZ model")
                    .accessibilityLabel("Generate Model")
                    .accessibilityHint("Run Apple Object Capture with selected images")
                }

                if let outputURL = viewModel.outputURL {
                    Button {
                        NSWorkspace.shared.open(outputURL)
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }
                    .help("Open the generated USDZ model")
                    .accessibilityLabel("Open Model")
                    .accessibilityHint("Open the generated USDZ file in Finder or default app")

                    Button {
                        presentSavePanel(for: outputURL)
                    } label: {
                        Label("Save…", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!viewModel.canSaveGeneratedModel)
                    .help("Save the generated model with a custom name")
                    .accessibilityLabel("Save Model")
                    .accessibilityHint("Choose where to save the generated USDZ model")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Processing Status")
        .accessibilityValue(presentation.title)
    }

    private func presentSavePanel(for outputURL: URL) {
        let panel = NSSavePanel()
        if let usdzType = UTType(filenameExtension: "usdz") {
            panel.allowedContentTypes = [usdzType]
        }
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Model.usdz"
        panel.directoryURL = outputURL.deletingLastPathComponent()

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        do {
            try viewModel.saveGeneratedModel(to: destinationURL)
        } catch {
            viewModel.state = .failed(message: "Unable to save model: \(error.localizedDescription)")
        }
    }

    private func color(for tone: StatusPresentation.Tone) -> Color {
        switch tone {
        case .secondary:
            return .secondary
        case .success:
            return .green
        case .error:
            return .red
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
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: imageURL) {
            await loadThumbnailIfNeeded()
        }
        .accessibilityLabel(imageURL.lastPathComponent)
    }

    @MainActor
    private func loadThumbnailIfNeeded() async {
        guard image == nil, !isLoading else { return }
        isLoading = true

        let loaded = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.makeThumbnail(from: imageURL, maxPixelSize: 200))
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
