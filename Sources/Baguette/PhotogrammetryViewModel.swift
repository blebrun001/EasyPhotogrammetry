import Foundation
import RealityKit

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
    struct EphemeralFeedback: Equatable, Identifiable {
        let id = UUID()
        let message: String
    }

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
    @Published var scalingResultMessage: String = ""
    @Published private(set) var ephemeralFeedback: EphemeralFeedback?
    @Published private(set) var isScaling = false
    @Published private(set) var measurementPhase: MeasurementPhase = .idle
    @Published private(set) var scalingSuccessCount = 0

    private let service: PhotogrammetryServicing
    private let scalingUseCase: ScalingUseCase
    private let isPhotogrammetrySupported: () -> Bool
    private let fileManager: FileManaging
    private var generationTask: Task<Void, Never>?
    private var scalingTask: Task<Void, Never>?
    private var feedbackDismissTask: Task<Void, Never>?
    private var generatedModelURL: URL?
    private var scaledModelURL: URL?

    init(
        service: PhotogrammetryServicing,
        scalingUseCase: ScalingUseCase = DefaultScalingUseCase(),
        isPhotogrammetrySupported: @escaping () -> Bool = { PhotogrammetrySession.isSupported },
        fileManager: FileManaging = FileManager.default
    ) {
        self.service = service
        self.scalingUseCase = scalingUseCase
        self.isPhotogrammetrySupported = isPhotogrammetrySupported
        self.fileManager = fileManager

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

    var hasImportedImages: Bool {
        !droppedImageURLs.isEmpty
    }

    var hasGeneratedPhotogrammetryModel: Bool {
        if generatedModelURL != nil {
            return true
        }
        if case .completed = state {
            return true
        }
        return false
    }

    var canScaleModel: Bool {
        guard !isScaling else { return false }
        guard selectedScaleFileURL != nil else { return false }
        guard let realValue = Double(realMeasurement), realValue > 0 else { return false }
        guard let uncalibratedValue = Double(uncalibratedMeasurement), uncalibratedValue > 0 else { return false }
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
        scalingTask?.cancel()
        scalingTask = nil
        droppedImageURLs = []
        generatedModelURL = nil
        scaledModelURL = nil
        scalingSuccessCount = 0
        state = .idle
        showEphemeralFeedback("Photo selection has been successfully cleared.")
    }

    func removeImage(_ url: URL) {
        guard canImportImages else { return }
        guard let index = droppedImageURLs.firstIndex(of: url) else { return }

        generationTask?.cancel()
        generationTask = nil
        scalingTask?.cancel()
        scalingTask = nil

        droppedImageURLs.remove(at: index)
        generatedModelURL = nil
        scaledModelURL = nil
        scalingSuccessCount = 0
        resetMeasurementState(clearUncalibrated: true)
        state = droppedImageURLs.isEmpty ? .idle : .ready
    }

    func generateModel() {
        guard canGenerateModel else { return }
        generationTask?.cancel()
        showEphemeralFeedback("3D model generation has started.")
        generationTask = Task { [weak self] in
            await self?.runGeneration()
        }
    }

    func cancelGeneration() {
        guard canCancelGeneration else { return }
        generationTask?.cancel()
        generationTask = nil
        state = .cancelled
        showEphemeralFeedback("3D model generation has been cancelled.")
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
        showEphemeralFeedback("3D model has been successfully saved.")
    }

    func handleImportFailure(_ error: Error) {
        state = .failed(message: "Unable to import images: \(error.localizedDescription)")
    }

    func handleSaveFailure(_ error: Error) {
        state = .failed(message: "Unable to save model: \(error.localizedDescription)")
    }

    func scaleModel() {
        guard canScaleModel else { return }
        scalingTask?.cancel()

        isScaling = true
        showEphemeralFeedback("3D model scaling has started.")

        let currentScaleFileURL = selectedScaleFileURL
        let currentUncalibratedMeasurement = uncalibratedMeasurement
        let currentRealMeasurement = realMeasurement
        let scalingUseCase = self.scalingUseCase

        scalingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isScaling = false
                scalingTask = nil
            }

            do {
                let request = try scalingUseCase.makeRequest(
                    file: currentScaleFileURL,
                    uncalibrated: currentUncalibratedMeasurement,
                    real: currentRealMeasurement
                )
                let resultURL = try await scalingUseCase.execute(request)
                guard !Task.isCancelled else { return }

                scaledModelURL = resultURL
                self.selectedScaleFileURL = resultURL
                scalingSuccessCount += 1
                scalingResultMessage = "Scaled model: \(resultURL.lastPathComponent)"
                showEphemeralFeedback("3D model has been successfully scaled.")
            } catch {
                guard !Task.isCancelled else { return }
                scalingResultMessage = "Scaling error: \(error.localizedDescription)"
            }
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

        if update.phase == .done {
            showEphemeralFeedback("Uncalibrated measurement has been successfully acquired.")
        }
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
            scalingSuccessCount = 0
            selectedScaleFileURL = outputURL
            scalingResultMessage = ""
            resetMeasurementState(clearUncalibrated: true)
            state = .completed(url: outputURL)
            showEphemeralFeedback("3D model has been successfully generated.")
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
        scalingSuccessCount = 0
        resetMeasurementState(clearUncalibrated: true)
        state = .ready
        showEphemeralFeedback("Photos have been successfully imported (\(droppedImageURLs.count)).")
    }

    func clearEphemeralFeedback() {
        feedbackDismissTask?.cancel()
        feedbackDismissTask = nil
        ephemeralFeedback = nil
    }

    private func showEphemeralFeedback(_ message: String, durationNanoseconds: UInt64 = 2_500_000_000) {
        feedbackDismissTask?.cancel()
        ephemeralFeedback = EphemeralFeedback(message: message)

        feedbackDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: durationNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.ephemeralFeedback = nil
            }
        }
    }

    private static func uniquePreservingOrder(_ urls: [URL]) -> [URL] {
        var seen: Set<URL> = []
        var result: [URL] = []

        for url in urls where seen.insert(url).inserted {
            result.append(url)
        }

        return result
    }

    deinit {
        generationTask?.cancel()
        scalingTask?.cancel()
        feedbackDismissTask?.cancel()
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
