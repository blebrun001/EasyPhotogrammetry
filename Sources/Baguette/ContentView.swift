import AppKit
import ImageIO
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var viewModel: PhotogrammetryViewModel
    @State private var selectedTab: AppTab = .importPhotos

    var body: some View {
        TabView(selection: $selectedTab) {
            ImportPhotosTabView(viewModel: viewModel)
                .tabItem {
                    tabLabel("Import", systemImage: "photo.on.rectangle", isEnabled: true)
                }
                .tag(AppTab.importPhotos)

            ProcessSettingsTabView(viewModel: viewModel)
                .tabItem {
                    tabLabel("Process", systemImage: "slider.horizontal.3", isEnabled: canAccessProcess)
                }
                .tag(AppTab.process)
                .disabled(!canAccessProcess)

            ScaleTabView(viewModel: viewModel)
                .tabItem {
                    tabLabel("Scale", systemImage: "ruler", isEnabled: canAccessScale)
                }
                .tag(AppTab.scale)
                .disabled(!canAccessScale)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    guard let outputURL = viewModel.outputURL else { return }
                    presentSavePanel(for: outputURL)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(!canShareModel)
                .help("Share model")
                .accessibilityLabel("Share")
            }
        }
        .onAppear {
            selectedTab = enforceTabAccess(for: selectedTab)
        }
        .onChange(of: selectedTab) { _, newTab in
            let accessibleTab = enforceTabAccess(for: newTab)
            guard accessibleTab == newTab else {
                selectedTab = accessibleTab
                return
            }
        }
        .onChange(of: canAccessProcess) { _, _ in
            selectedTab = enforceTabAccess(for: selectedTab)
        }
        .onChange(of: canAccessScale) { _, _ in
            selectedTab = enforceTabAccess(for: selectedTab)
        }
    }

    private var canAccessProcess: Bool {
        viewModel.hasImportedImages
    }

    private var canAccessScale: Bool {
        viewModel.hasGeneratedPhotogrammetryModel
    }

    private var canShareModel: Bool {
        viewModel.hasExportableModel
    }

    @ViewBuilder
    private func tabLabel(_ title: String, systemImage: String, isEnabled: Bool) -> some View {
        Label {
            Text(title)
                .foregroundColor(isEnabled ? .primary : .gray)
        } icon: {
            Image(systemName: systemImage)
                .foregroundColor(isEnabled ? .primary : .gray)
        }
    }

    private func enforceTabAccess(for requestedTab: AppTab) -> AppTab {
        switch requestedTab {
        case .importPhotos:
            return .importPhotos
        case .process:
            return canAccessProcess ? .process : .importPhotos
        case .scale:
            if canAccessScale { return .scale }
            if canAccessProcess { return .process }
            return .importPhotos
        }
    }

    private func presentSavePanel(for outputURL: URL) {
        let panel = NSSavePanel()
        if let usdzType = UTType(filenameExtension: "usdz") {
            panel.allowedContentTypes = [usdzType]
        }
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Model.usdz"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? outputURL.deletingLastPathComponent()

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        do {
            try viewModel.saveGeneratedModel(to: destinationURL)
        } catch {
            viewModel.state = .failed(message: "Unable to save model: \(error.localizedDescription)")
        }
    }
}

private enum AppTab: Hashable {
    case importPhotos
    case process
    case scale
}

private struct ProcessSettingsTabView: View {
    @ObservedObject var viewModel: PhotogrammetryViewModel

    var body: some View {
        VStack(spacing: 12) {
            Form {
                Section("Configuration") {
                    configurationSection
                }

                Section("Status") {
                    statusSection
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: .infinity)

            HStack {
                Spacer()
                actionButton
                Spacer()
            }
        }
        .padding(16)
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

    private var statusSection: some View {
        let presentation = viewModel.state.presentation

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let symbolName = presentation.symbolName {
                    Image(systemName: symbolName)
                        .foregroundStyle(color(for: presentation.tone))
                }

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
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Processing Status")
        .accessibilityValue(presentation.title)
    }

    private var actionButton: some View {
        Group {
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
                    Text("Generate")
                        .frame(minWidth: 140)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canGenerateModel)
                .help("Generate a USDZ model")
                .accessibilityLabel("Generate Model")
                .accessibilityHint("Run Apple Object Capture with selected images")
            }
        }
        .controlSize(.large)
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

private struct ScaleTabView: View {
    @ObservedObject var viewModel: PhotogrammetryViewModel
    @State private var isMeasurementModeEnabled = false
    @State private var editingCommand: MeasurementEditingCommand = .none
    @State private var editingCommandToken = UUID()
    @State private var measurementUpdate: MeasurementUpdate = .idle

    var body: some View {
        VStack(spacing: 12) {
            Form {
                Section("Measurements") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Button {
                                toggleMeasurementMode()
                            } label: {
                                Label(
                                    isMeasurementModeEnabled ? "Disable measurement" : "Enable measurement",
                                    systemImage: isMeasurementModeEnabled ? "pause.circle" : "dot.scope"
                                )
                            }
                            .disabled(viewModel.selectedScaleFileURL == nil)

                            Button {
                                sendEditingCommand(.reset)
                            } label: {
                                Label("Reset", systemImage: "trash")
                            }
                            .disabled(viewModel.selectedScaleFileURL == nil || measurementUpdate.pointCount == 0)

                            Spacer()
                        }

                        SurfaceMeasurementView(
                            modelURL: viewModel.selectedScaleFileURL,
                            isMeasurementModeEnabled: isMeasurementModeEnabled,
                            editingCommand: editingCommand,
                            editingCommandToken: editingCommandToken
                        ) { update in
                            measurementUpdate = update
                            viewModel.handleMeasurementUpdate(update)
                            viewModel.scalingResultMessage = ""

                            if update.phase == .done {
                                isMeasurementModeEnabled = false
                            }
                        }
                        .frame(minHeight: 260, maxHeight: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    TextField("Calibrated measure (cm)", text: $viewModel.realMeasurement)
                        .textFieldStyle(.roundedBorder)

                    if !viewModel.scalingResultMessage.isEmpty {
                        Text(viewModel.scalingResultMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: .infinity)

            HStack {
                Spacer()
                actionButton
                Spacer()
            }
        }
        .padding(16)
        .onChange(of: viewModel.selectedScaleFileURL) { _, _ in
            resetMeasurementUI()
        }
    }

    private var actionButton: some View {
        Button {
            viewModel.scaleModel()
        } label: {
            Text("Start scaling")
                .frame(minWidth: 140)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!viewModel.canScaleModel)
        .controlSize(.large)
    }

    private func toggleMeasurementMode() {
        isMeasurementModeEnabled.toggle()
        sendEditingCommand(.none)
    }

    private func sendEditingCommand(_ command: MeasurementEditingCommand) {
        editingCommand = command
        editingCommandToken = UUID()
    }

    private func resetMeasurementUI() {
        isMeasurementModeEnabled = false
        measurementUpdate = .idle
        sendEditingCommand(.reset)
        viewModel.resetMeasurementState(clearUncalibrated: true)
    }
}

private struct ImportPhotosTabView: View {
    @ObservedObject var viewModel: PhotogrammetryViewModel

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
                        Label("Clean all", systemImage: "xmark")
                    }
                    .disabled(!viewModel.canClearSelection)
                    .help("Clear selected images")
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
                Image(systemName: "tray.and.arrow.down")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                        ForEach(viewModel.droppedImageURLs, id: \.self) { imageURL in
                            ThumbnailView(
                                imageURL: imageURL,
                                canRemove: viewModel.canImportImages,
                                onRemove: { viewModel.removeImage(imageURL) }
                            )
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
}

private struct Export3DTabView: View {
    let modelURL: URL?
    let instanceID: UUID
    let onSaveModel: (URL) -> Void

    var body: some View {
        Form {
            Section("Preview") {
                ZStack {
                    ExportModelPreview(url: modelURL)
                        .id(instanceID)

                    if modelURL == nil {
                        unavailablePlaceholder
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 320, maxHeight: 460)
            }

            Section("Export") {
                if let modelURL {
                    Button {
                        onSaveModel(modelURL)
                    } label: {
                        Label("Save…", systemImage: "square.and.arrow.down")
                    }
                    .help("Save the generated model with a custom name")
                    .accessibilityLabel("Save Model")
                    .accessibilityHint("Choose where to save the generated USDZ model")
                } else {
                    Text("No model available for export.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }

    private var unavailablePlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("No 3D model available yet")
                .font(.headline)
            Text("Generate and scale a model to enable export.")
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct ExportModelPreview: NSViewRepresentable {
    let url: URL?

    final class Coordinator {
        var currentURL: URL?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .windowBackgroundColor
        view.scene = SCNScene()
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        guard context.coordinator.currentURL != url else { return }
        context.coordinator.currentURL = url

        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            nsView.scene = SCNScene()
            return
        }

        do {
            nsView.scene = try SCNScene(url: url, options: nil)
        } catch {
            nsView.scene = SCNScene()
        }
    }

    static func dismantleNSView(_ nsView: SCNView, coordinator: Coordinator) {
        coordinator.currentURL = nil
        nsView.scene = nil
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
        .frame(width: 72, height: 72)
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
            .help("Remove this photo")
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
