import Foundation
import RealityKit

/// User-facing quality presets mapped to Object Capture detail levels.
enum ModelQuality: String, CaseIterable, Identifiable {
    case low
    case normal
    case high

    var id: String { rawValue }

    /// Full display label used by the quality picker.
    var label: String {
        switch self {
        case .low:
            return "Low"
        case .normal:
            return "Normal"
        case .high:
            return "High"
        }
    }

    /// Compact label used when horizontal space is constrained.
    var shortLabel: String {
        switch self {
        case .low:
            return "Low"
        case .normal:
            return "Normal"
        case .high:
            return "High"
        }
    }

    /// RealityKit detail level associated with this quality preset.
    var detail: PhotogrammetrySession.Request.Detail {
        switch self {
        case .low:
            return .preview
        case .normal:
            return .medium
        case .high:
            return .full
        }
    }
}

/// Main UI state holder for drag-and-drop and model generation flow.
@MainActor
final class PhotogrammetryViewModel: ObservableObject {
    /// Short-lived feedback message displayed as a transient top banner.
    struct EphemeralFeedback: Equatable, Identifiable {
        let id = UUID()
        let message: String
    }

    @Published private(set) var droppedImageURLs: [URL] = []
    @Published var state: ProcessingState = .idle
    @Published var isDropTargeted = false
    @Published var selectedQuality: ModelQuality = .high {
        didSet {
            guard selectedQuality != oldValue else { return }
            handleSelectedQualityChange(from: oldValue, to: selectedQuality)
        }
    }
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
    private var prewarmCatchUpTask: Task<Void, Never>?
    private var generatedModelURL: URL?
    private var scaledModelURL: URL?
    private var prewarmGeneration: PrewarmGeneration?

    /// Tracks a high-quality generation started ahead of explicit user confirmation.
    private struct PrewarmGeneration {
        let token: UUID
        let imageSnapshot: [URL]
        var task: Task<URL, Error>?
        var observerTask: Task<Void, Never>?
        var outputURL: URL?
        var latestProgress: Double = 0
        var isPromoted = false
    }

    /// - Parameters:
    ///   - service: Photogrammetry service used to generate USDZ models.
    ///   - scalingUseCase: Use case in charge of validating and executing scale operations.
    ///   - isPhotogrammetrySupported: Capability check for current machine.
    ///   - fileManager: File-system dependency used when exporting models.
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

    /// Indicates whether generation can start based on support, selected images, and current state.
    var canGenerateModel: Bool {
        guard isPhotogrammetrySupported() else { return false }
        guard !droppedImageURLs.isEmpty else { return false }

        if case .processing = state {
            return false
        }

        return true
    }

    /// Indicates whether an in-flight generation can be cancelled.
    var canCancelGeneration: Bool {
        if case .processing = state {
            return true
        }
        return false
    }

    /// Indicates whether the user can import new images in the current state.
    var canImportImages: Bool {
        guard isPhotogrammetrySupported() else { return false }
        if case .processing = state {
            return false
        }
        return true
    }

    /// Indicates whether selected images can be cleared.
    var canClearSelection: Bool {
        !droppedImageURLs.isEmpty && canImportImages
    }

    /// Most recent output URL, preferring scaled outputs over raw generated outputs.
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

    /// Convenience flag indicating whether at least one photo has been imported.
    var hasImportedImages: Bool {
        !droppedImageURLs.isEmpty
    }

    /// Indicates whether a photogrammetry model has been generated in the current session.
    var hasGeneratedPhotogrammetryModel: Bool {
        if generatedModelURL != nil {
            return true
        }
        if case .completed = state {
            return true
        }
        return false
    }

    /// Indicates whether scaling can start with the current inputs.
    var canScaleModel: Bool {
        guard !isScaling else { return false }
        guard selectedScaleFileURL != nil else { return false }
        guard let realValue = DefaultScalingUseCase.parseMeasurementValue(realMeasurement), realValue > 0 else {
            return false
        }
        guard let uncalibratedValue = DefaultScalingUseCase.parseMeasurementValue(uncalibratedMeasurement),
              uncalibratedValue > 0 else {
            return false
        }
        return true
    }

    /// Opens the file importer if importing is currently allowed.
    func presentImportPicker() {
        guard canImportImages else { return }
        isImportPickerPresented = true
    }

    /// Handles imported image URLs and merges/replaces them according to import behavior.
    /// - Parameters:
    ///   - urls: Imported image URLs.
    ///   - behavior: Merge strategy for incoming URLs.
    func handleImportedImageURLs(_ urls: [URL], behavior: ImportBehavior = .append) {
        guard canImportImages else { return }
        setImages(urls, behavior: behavior)
    }

    /// Clears current selection and resets generation/scaling state.
    func clearSelection() {
        guard canClearSelection else { return }
        invalidatePrewarm(cleanupOutput: true)
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

    /// Removes one image from the selection and resets derived outputs.
    /// - Parameter url: Image URL to remove.
    func removeImage(_ url: URL) {
        guard canImportImages else { return }
        guard let index = droppedImageURLs.firstIndex(of: url) else { return }

        invalidatePrewarm(cleanupOutput: true)
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

    /// Starts generation or promotes an existing high-quality prewarm generation.
    func generateModel() {
        guard canGenerateModel else { return }
        generationTask?.cancel()
        showEphemeralFeedback("3D model generation has started.")

        if selectedQuality == .high {
            let snapshot = droppedImageURLs
            if let prewarmGeneration, prewarmGeneration.imageSnapshot == snapshot {
                if let outputURL = prewarmGeneration.outputURL {
                    completeGeneration(with: outputURL)
                    clearPrewarmGeneration(cleanupOutput: false)
                    return
                }

                promotePrewarmGeneration(token: prewarmGeneration.token)
                return
            }

            invalidatePrewarm(cleanupOutput: true)
        } else {
            invalidatePrewarm(cleanupOutput: true)
        }

        generationTask = Task { [weak self] in
            await self?.runGeneration()
        }
    }

    /// Cancels active generation and updates state to cancelled.
    func cancelGeneration() {
        guard canCancelGeneration else { return }
        generationTask?.cancel()
        generationTask = nil

        if let prewarmGeneration, prewarmGeneration.isPromoted {
            prewarmGeneration.task?.cancel()
            clearPrewarmGeneration(cleanupOutput: true)
        }

        state = .cancelled
        showEphemeralFeedback("3D model generation has been cancelled.")
    }

    /// Saves the current output model to a destination URL selected by the user.
    /// - Parameter destinationURL: User-selected destination path (extension may be omitted).
    /// - Throws: Any file-system error while replacing/copying the file.
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

    /// Converts import errors into user-facing processing state.
    func handleImportFailure(_ error: Error) {
        state = .failed(message: "Unable to import images: \(error.localizedDescription)")
    }

    /// Converts save errors into user-facing processing state.
    func handleSaveFailure(_ error: Error) {
        state = .failed(message: "Unable to save model: \(error.localizedDescription)")
    }

    /// Validates and executes model scaling asynchronously.
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
                    real: currentRealMeasurement,
                    overwrite: false
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

    /// Applies measured distance from SceneKit into the uncalibrated input field.
    /// - Parameter distance: Measured model distance.
    func applyMeasuredUncalibratedDistance(_ distance: Double) {
        guard distance.isFinite, distance > 0 else { return }
        uncalibratedMeasurement = String(format: "%.6f", distance)
    }

    /// Handles measurement updates coming from the SceneKit measurement view.
    /// - Parameter update: Latest measurement update snapshot.
    func handleMeasurementUpdate(_ update: MeasurementUpdate) {
        measurementPhase = update.phase

        guard let distance = update.distance else { return }
        applyMeasuredUncalibratedDistance(distance)

        if update.phase == .done {
            showEphemeralFeedback("Uncalibrated measurement has been successfully acquired.")
        }
    }

    /// Resets measurement phase and optionally clears the uncalibrated value.
    /// - Parameter clearUncalibrated: Whether to clear `uncalibratedMeasurement`.
    func resetMeasurementState(clearUncalibrated: Bool) {
        measurementPhase = .idle
        if clearUncalibrated {
            uncalibratedMeasurement = ""
        }
    }

    /// Runs generation against the current image selection and updates progress/state.
    private func runGeneration() async {
        guard !Task.isCancelled else { return }

        let processingFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self else { return }
            guard self.generationTask != nil else { return }
            if case .processing = self.state { return }
            self.state = .processing(progress: 0)
        }
        defer { processingFallbackTask.cancel() }

        do {
            let outputURL = try await service.generateUSDZ(
                from: droppedImageURLs,
                detail: selectedQuality.detail,
                onProgress: { [weak self] progress in
                    guard let self else { return }
                    if Thread.isMainThread {
                        MainActor.assumeIsolated {
                            self.updateGenerationProgress(progress)
                        }
                    } else {
                        DispatchQueue.main.sync {
                            MainActor.assumeIsolated {
                                self.updateGenerationProgress(progress)
                            }
                        }
                    }
                }
            )
            guard !Task.isCancelled else {
                state = .cancelled
                generationTask = nil
                return
            }
            completeGeneration(with: outputURL)
        } catch is CancellationError {
            state = .cancelled
        } catch {
            state = .failed(message: error.localizedDescription)
        }

        generationTask = nil
    }

    /// Clamps progress values into the `[0, 1]` range.
    private static func clampProgress(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    /// Filters/merges imported URLs, resets derived state, and optionally starts high-quality prewarm.
    /// - Parameters:
    ///   - urls: Imported image URLs.
    ///   - behavior: Merge strategy for incoming URLs.
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

        invalidatePrewarm(cleanupOutput: true)
        droppedImageURLs = Self.uniquePreservingOrder(merged)
        generatedModelURL = nil
        scaledModelURL = nil
        scalingSuccessCount = 0
        resetMeasurementState(clearUncalibrated: true)
        state = .ready
        showEphemeralFeedback("Photos have been successfully imported (\(droppedImageURLs.count)).")

        maybeStartPrewarmGeneration()
    }

    /// Reacts to quality changes by starting or invalidating high-quality prewarm generation.
    /// - Parameters:
    ///   - oldValue: Previous quality value.
    ///   - newValue: Newly selected quality value.
    private func handleSelectedQualityChange(from oldValue: ModelQuality, to newValue: ModelQuality) {
        guard canImportImages else { return }

        if newValue == .high {
            maybeStartPrewarmGeneration(forceRestart: oldValue != .high)
            return
        }

        invalidatePrewarm(cleanupOutput: true)
    }

    /// Starts a detached high-quality generation to reduce perceived latency on Generate.
    /// - Parameter forceRestart: Whether to restart even when snapshot did not change.
    private func maybeStartPrewarmGeneration(forceRestart: Bool = false) {
        guard selectedQuality == .high else { return }
        guard !droppedImageURLs.isEmpty else { return }
        guard canImportImages else { return }

        let snapshot = droppedImageURLs
        if let prewarmGeneration {
            if !forceRestart, prewarmGeneration.imageSnapshot == snapshot {
                return
            }
            invalidatePrewarm(cleanupOutput: true)
        }

        let token = UUID()
        let service = self.service
        var generation = PrewarmGeneration(
            token: token,
            imageSnapshot: snapshot,
            task: nil,
            observerTask: nil,
            outputURL: nil
        )
        prewarmGeneration = generation

        let task = Task.detached(priority: .userInitiated) { [snapshot] in
            try Task.checkCancellation()
            return try await service.generateUSDZ(
                from: snapshot,
                detail: .full,
                onProgress: { [weak self] progress in
                    guard let self else { return }
                    if Thread.isMainThread {
                        MainActor.assumeIsolated {
                            self.handlePrewarmProgress(token: token, progress: progress)
                        }
                    } else {
                        DispatchQueue.main.sync {
                            self.handlePrewarmProgress(token: token, progress: progress)
                        }
                    }
                }
            )
        }

        generation.task = task
        generation.observerTask = Task { [weak self] in
            guard let self else { return }
            do {
                let outputURL = try await task.value
                await MainActor.run {
                    self.handlePrewarmSuccess(token: token, outputURL: outputURL)
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    self.handlePrewarmFailure(token: token, error: error)
                }
            }
        }
        prewarmGeneration = generation
    }

    /// Promotes a completed/in-flight prewarm generation into the active generation UI flow.
    /// - Parameter token: Token identifying the prewarm generation to promote.
    private func promotePrewarmGeneration(token: UUID) {
        guard var prewarmGeneration, prewarmGeneration.token == token, let task = prewarmGeneration.task else { return }
        prewarmGeneration.isPromoted = true
        self.prewarmGeneration = prewarmGeneration

        state = .processing(progress: prewarmGeneration.latestProgress)
        startPrewarmProgressCatchUp(to: prewarmGeneration.latestProgress, token: token)
        generationTask = Task { [task] in
            _ = try? await task.value
        }
    }

    /// Stores latest prewarm progress and updates visible progress when promoted.
    /// - Parameters:
    ///   - token: Generation token.
    ///   - progress: Latest progress value.
    private func handlePrewarmProgress(token: UUID, progress: Double) {
        guard var prewarmGeneration, prewarmGeneration.token == token else { return }
        let clampedProgress = Self.clampProgress(progress)
        prewarmGeneration.latestProgress = max(prewarmGeneration.latestProgress, clampedProgress)
        self.prewarmGeneration = prewarmGeneration

        guard prewarmGeneration.isPromoted else { return }
        guard case .processing(let currentProgress) = state else { return }

        let nextProgress = max(currentProgress, prewarmGeneration.latestProgress)
        prewarmCatchUpTask?.cancel()
        prewarmCatchUpTask = nil
        state = .processing(progress: nextProgress)
    }

    /// Handles successful prewarm completion and finalizes state when promoted.
    /// - Parameters:
    ///   - token: Generation token.
    ///   - outputURL: Generated output URL.
    private func handlePrewarmSuccess(token: UUID, outputURL: URL) {
        guard var prewarmGeneration, prewarmGeneration.token == token else {
            service.cleanupGeneratedModel(at: outputURL)
            return
        }

        prewarmGeneration.outputURL = outputURL
        self.prewarmGeneration = prewarmGeneration

        guard prewarmGeneration.isPromoted else { return }

        completeGeneration(with: outputURL)
        generationTask = nil
        clearPrewarmGeneration(cleanupOutput: false)
    }

    /// Handles prewarm failure and surfaces errors only when prewarm was promoted.
    /// - Parameters:
    ///   - token: Generation token.
    ///   - error: Underlying generation error.
    private func handlePrewarmFailure(token: UUID, error: Error) {
        guard let prewarmGeneration, prewarmGeneration.token == token else { return }

        if prewarmGeneration.isPromoted {
            state = .failed(message: error.localizedDescription)
            generationTask = nil
        }

        clearPrewarmGeneration(cleanupOutput: false)
    }

    /// Invalidates current prewarm generation if one exists.
    /// - Parameter cleanupOutput: Whether to delete produced prewarm output.
    private func invalidatePrewarm(cleanupOutput: Bool) {
        guard prewarmGeneration != nil else { return }
        clearPrewarmGeneration(cleanupOutput: cleanupOutput)
    }

    /// Cancels and clears prewarm tasks, optionally cleaning generated output.
    /// - Parameter cleanupOutput: Whether to delete produced prewarm output.
    private func clearPrewarmGeneration(cleanupOutput: Bool) {
        guard let prewarmGeneration else { return }

        prewarmCatchUpTask?.cancel()
        prewarmCatchUpTask = nil
        prewarmGeneration.task?.cancel()
        prewarmGeneration.observerTask?.cancel()
        self.prewarmGeneration = nil

        guard cleanupOutput, let outputURL = prewarmGeneration.outputURL else { return }
        service.cleanupGeneratedModel(at: outputURL)
    }

    /// Applies successful generation output to state and resets scale-related transient data.
    /// - Parameter outputURL: Generated model URL.
    private func completeGeneration(with outputURL: URL) {
        prewarmCatchUpTask?.cancel()
        prewarmCatchUpTask = nil
        generatedModelURL = outputURL
        scaledModelURL = nil
        scalingSuccessCount = 0
        selectedScaleFileURL = outputURL
        scalingResultMessage = ""
        resetMeasurementState(clearUncalibrated: true)
        state = .completed(url: outputURL)
        showEphemeralFeedback("3D model has been successfully generated.")
    }

    /// Smoothly catches up visible progress to the latest prewarm progress when promoted.
    /// - Parameters:
    ///   - targetProgress: Initial target progress.
    ///   - token: Generation token used to ensure task relevance.
    private func startPrewarmProgressCatchUp(to targetProgress: Double, token: UUID) {
        let clampedTarget = Self.clampProgress(targetProgress)
        guard clampedTarget > 0 else { return }

        prewarmCatchUpTask?.cancel()
        prewarmCatchUpTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 35_000_000)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let prewarmGeneration = self.prewarmGeneration,
                          prewarmGeneration.token == token,
                          prewarmGeneration.isPromoted else {
                        self.prewarmCatchUpTask?.cancel()
                        self.prewarmCatchUpTask = nil
                        return
                    }
                    guard case .processing(let currentProgress) = self.state else {
                        self.prewarmCatchUpTask?.cancel()
                        self.prewarmCatchUpTask = nil
                        return
                    }

                    let effectiveTarget = max(clampedTarget, prewarmGeneration.latestProgress)
                    let nextProgress = min(effectiveTarget, currentProgress + 0.08)
                    if nextProgress > currentProgress {
                        self.state = .processing(progress: nextProgress)
                    }
                    if nextProgress >= effectiveTarget {
                        self.prewarmCatchUpTask?.cancel()
                        self.prewarmCatchUpTask = nil
                    }
                }
            }
        }
    }

    /// Updates visible generation progress after clamping and cancellation checks.
    /// - Parameter progress: Raw progress value.
    private func updateGenerationProgress(_ progress: Double) {
        guard !Task.isCancelled else { return }
        state = .processing(progress: Self.clampProgress(progress))
    }

    /// Immediately clears the currently displayed transient feedback banner.
    func clearEphemeralFeedback() {
        feedbackDismissTask?.cancel()
        feedbackDismissTask = nil
        ephemeralFeedback = nil
    }

    /// Shows a transient feedback message and auto-clears it after a delay.
    /// - Parameters:
    ///   - message: Message to display.
    ///   - durationNanoseconds: Visibility duration before auto-dismiss.
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

    /// De-duplicates URLs while preserving their first-seen order.
    /// - Parameter urls: Input URL list.
    /// - Returns: Unique URL list preserving initial ordering.
    private static func uniquePreservingOrder(_ urls: [URL]) -> [URL] {
        var seen: Set<URL> = []
        var result: [URL] = []

        for url in urls where seen.insert(url).inserted {
            result.append(url)
        }

        return result
    }

    /// Cancels all in-flight tasks to avoid leaked background work on deallocation.
    deinit {
        generationTask?.cancel()
        scalingTask?.cancel()
        feedbackDismissTask?.cancel()
        prewarmCatchUpTask?.cancel()
        prewarmGeneration?.task?.cancel()
        prewarmGeneration?.observerTask?.cancel()
    }
}

/// Describes how a new import batch should be merged with the current image selection.
enum ImportBehavior {
    case append
    case replace
}

/// Minimal file-system API injected into the view model for easier testing.
protocol FileManaging {
    func fileExists(atPath path: String) -> Bool
    func removeItem(at URL: URL) throws
    func copyItem(at srcURL: URL, to dstURL: URL) throws
}

/// Production `FileManaging` conformance.
extension FileManager: FileManaging {}
