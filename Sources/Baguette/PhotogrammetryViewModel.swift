import Foundation
import RealityKit
import UniformTypeIdentifiers

enum ModelQuality: String, CaseIterable, Identifiable {
    case preview
    case reduced
    case medium
    case full
    case raw

    var id: String { rawValue }

    var label: String {
        switch self {
        case .preview:
            return "Preview (fast)"
        case .reduced:
            return "Reduced"
        case .medium:
            return "Medium"
        case .full:
            return "High"
        case .raw:
            return "Raw (max)"
        }
    }

    var shortLabel: String {
        switch self {
        case .preview:
            return "Preview"
        case .reduced:
            return "Reduced"
        case .medium:
            return "Medium"
        case .full:
            return "Full"
        case .raw:
            return "Raw"
        }
    }

    var detail: PhotogrammetrySession.Request.Detail {
        switch self {
        case .preview:
            return .preview
        case .reduced:
            return .reduced
        case .medium:
            return .medium
        case .full:
            return .full
        case .raw:
            return .raw
        }
    }
}

/// Main UI state holder for drag-and-drop and model generation flow.
@MainActor
final class PhotogrammetryViewModel: ObservableObject {
    @Published private(set) var droppedImageURLs: [URL] = []
    @Published var state: ProcessingState = .idle
    @Published var isDropTargeted = false
    @Published var selectedQuality: ModelQuality = .full
    @Published var isImportPickerPresented = false
    @Published var selectedScaleFileURL: URL? {
        didSet {
            guard selectedScaleFileURL != oldValue else { return }
            resetMeasurementState(clearUncalibrated: true)
        }
    }
    @Published var uncalibratedMeasurement: String = ""
    @Published var realMeasurement: String = ""
    @Published var overwriteScaledModel: Bool = true
    @Published var scalingResultMessage: String = ""
    @Published private(set) var isScaling = false
    @Published private(set) var measurementPhase: MeasurementPhase = .idle

    private let service: PhotogrammetryServicing
    private let scalingUseCase: ScalingUseCase
    private let isPhotogrammetrySupported: () -> Bool
    private let fileManager: FileManaging
    private let itemProviderLoader: ItemProviderLoading
    private var generationTask: Task<Void, Never>?
    private var generatedModelURL: URL?
    private var scaledModelURL: URL?

    init(
        service: PhotogrammetryServicing,
        scalingUseCase: ScalingUseCase = DefaultScalingUseCase(),
        isPhotogrammetrySupported: @escaping () -> Bool = { PhotogrammetrySession.isSupported },
        fileManager: FileManaging = FileManager.default,
        itemProviderLoader: ItemProviderLoading = DefaultItemProviderLoader()
    ) {
        self.service = service
        self.scalingUseCase = scalingUseCase
        self.isPhotogrammetrySupported = isPhotogrammetrySupported
        self.fileManager = fileManager
        self.itemProviderLoader = itemProviderLoader

        if !isPhotogrammetrySupported() {
            state = .failed(message: "This machine is not compatible with Apple photogrammetry.")
        }
    }

    var canGenerateModel: Bool {
        guard isPhotogrammetrySupported() else { return false }
        guard !droppedImageURLs.isEmpty else { return false }

        if case .processing = state {
            return false
        }

        return true
    }

    var canCancelGeneration: Bool {
        if case .processing = state {
            return true
        }
        return false
    }

    var canImportImages: Bool {
        guard isPhotogrammetrySupported() else { return false }
        if case .processing = state {
            return false
        }
        return true
    }

    var canClearSelection: Bool {
        !droppedImageURLs.isEmpty && canImportImages
    }

    var outputURL: URL? {
        if let scaledModelURL {
            return scaledModelURL
        }
        if let generatedModelURL {
            return generatedModelURL
        }
        if case .completed(let url) = state {
            return url
        }
        return nil
    }

    var canSaveGeneratedModel: Bool {
        outputURL != nil
    }

    var hasGeneratedModel: Bool {
        outputURL != nil
    }

    var canScaleModel: Bool {
        guard !isScaling else { return false }
        guard selectedScaleFileURL != nil else { return false }
        guard let realValue = Double(realMeasurement), realValue > 0 else { return false }
        guard let uncalibratedValue = Double(uncalibratedMeasurement), uncalibratedValue > 0 else { return false }
        return true
    }

    func handleDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        Task { @MainActor in
            var accepted: [URL] = []

            for provider in providers {
                guard itemProviderLoader.hasFileURL(provider) else {
                    continue
                }

                do {
                    let url = try await itemProviderLoader.loadFileURL(from: provider)
                    if SupportedImageFormat.isSupported(url) {
                        accepted.append(url)
                    }
                } catch {
                    continue
                }
            }

            if accepted.isEmpty {
                state = .failed(message: "No valid images detected (\(SupportedImageFormat.userFacingList)).")
                return
            }

            setImages(accepted, behavior: .replace)
        }

        return true
    }

    func presentImportPicker() {
        guard canImportImages else { return }
        isImportPickerPresented = true
    }

    func handleImportedImageURLs(_ urls: [URL], behavior: ImportBehavior = .append) {
        guard canImportImages else { return }
        setImages(urls, behavior: behavior)
    }

    func clearSelection() {
        guard canClearSelection else { return }
        generationTask?.cancel()
        generationTask = nil
        droppedImageURLs = []
        generatedModelURL = nil
        scaledModelURL = nil
        state = .idle
    }

    func generateModel() {
        guard canGenerateModel else { return }
        generationTask?.cancel()
        generationTask = Task { [weak self] in
            await self?.runGeneration()
        }
    }

    func cancelGeneration() {
        guard canCancelGeneration else { return }
        generationTask?.cancel()
        generationTask = nil
        state = .cancelled
    }

    func saveGeneratedModel(to destinationURL: URL) throws {
        guard let sourceURL = outputURL else { return }

        let finalDestination: URL
        if destinationURL.pathExtension.isEmpty {
            finalDestination = destinationURL.appendingPathExtension("usdz")
        } else {
            finalDestination = destinationURL
        }

        if fileManager.fileExists(atPath: finalDestination.path) {
            try fileManager.removeItem(at: finalDestination)
        }
        try fileManager.copyItem(at: sourceURL, to: finalDestination)
    }

    func scaleModel() {
        isScaling = true
        defer { isScaling = false }

        do {
            let request = try scalingUseCase.makeRequest(
                file: selectedScaleFileURL,
                uncalibrated: uncalibratedMeasurement,
                real: realMeasurement,
                overwrite: overwriteScaledModel
            )
            let resultURL = try scalingUseCase.execute(request)
            scaledModelURL = resultURL
            selectedScaleFileURL = resultURL
            scalingResultMessage = "Scaled model: \(resultURL.lastPathComponent)"
        } catch {
            scalingResultMessage = "Scaling error: \(error.localizedDescription)"
        }
    }

    func applyMeasuredUncalibratedDistance(_ distance: Double) {
        guard distance.isFinite, distance > 0 else { return }
        uncalibratedMeasurement = String(format: "%.6f", distance)
    }

    func handleMeasurementUpdate(_ update: MeasurementUpdate) {
        measurementPhase = update.phase

        guard let distance = update.distance else { return }
        applyMeasuredUncalibratedDistance(distance)
    }

    func resetMeasurementState(clearUncalibrated: Bool) {
        measurementPhase = .idle
        if clearUncalibrated {
            uncalibratedMeasurement = ""
        }
    }

    private func runGeneration() async {
        guard !Task.isCancelled else { return }

        state = .processing(progress: 0)

        do {
            let outputURL = try await service.generateUSDZ(
                from: droppedImageURLs,
                detail: selectedQuality.detail,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        guard let self else { return }
                        guard !Task.isCancelled else { return }
                        self.state = .processing(progress: Self.clampProgress(progress))
                    }
                }
            )
            guard !Task.isCancelled else {
                state = .cancelled
                generationTask = nil
                return
            }
            generatedModelURL = outputURL
            scaledModelURL = nil
            selectedScaleFileURL = outputURL
            scalingResultMessage = ""
            resetMeasurementState(clearUncalibrated: true)
            state = .completed(url: outputURL)
        } catch is CancellationError {
            state = .cancelled
        } catch {
            state = .failed(message: error.localizedDescription)
        }

        generationTask = nil
    }

    private static func clampProgress(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private func setImages(_ urls: [URL], behavior: ImportBehavior) {
        let filtered = urls.filter(SupportedImageFormat.isSupported)
        guard !filtered.isEmpty else {
            state = .failed(message: "No valid images detected (\(SupportedImageFormat.userFacingList)).")
            return
        }

        let merged: [URL]
        switch behavior {
        case .replace:
            merged = filtered
        case .append:
            merged = droppedImageURLs + filtered
        }

        droppedImageURLs = Self.uniquePreservingOrder(merged)
        generatedModelURL = nil
        scaledModelURL = nil
        resetMeasurementState(clearUncalibrated: true)
        state = .ready
    }

    private static func uniquePreservingOrder(_ urls: [URL]) -> [URL] {
        var seen: Set<URL> = []
        var result: [URL] = []

        for url in urls where seen.insert(url).inserted {
            result.append(url)
        }

        return result
    }
}

enum ImportBehavior {
    case append
    case replace
}

protocol FileManaging {
    func fileExists(atPath path: String) -> Bool
    func removeItem(at URL: URL) throws
    func copyItem(at srcURL: URL, to dstURL: URL) throws
}

extension FileManager: FileManaging {}

protocol ItemProviderLoading {
    func hasFileURL(_ provider: NSItemProvider) -> Bool
    @MainActor func loadFileURL(from provider: NSItemProvider) async throws -> URL
}

struct DefaultItemProviderLoader: ItemProviderLoading {
    func hasFileURL(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
    }

    @MainActor
    func loadFileURL(from provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }

                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                continuation.resume(throwing: CocoaError(.fileReadCorruptFile))
            }
        }
    }
}
