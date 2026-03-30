import Foundation
import RealityKit
import Testing
@testable import Baguette

@Suite("PhotogrammetryViewModel")
struct PhotogrammetryViewModelTests {
    @Test("initializes as failed on unsupported machine")
    @MainActor
    func unsupportedInitState() {
        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService { _, _, _ in URL(fileURLWithPath: "/tmp/never.usdz") },
            isPhotogrammetrySupported: { false }
        )

        #expect(viewModel.canImportImages == false)
        #expect(viewModel.canGenerateModel == false)
        if case .failed(let message) = viewModel.state {
            #expect(message.contains("not compatible"))
        } else {
            Issue.record("Expected .failed state on unsupported machine")
        }
    }

    @Test("import append/replace keeps order and deduplicates")
    @MainActor
    func importBehavior() {
        let viewModel = makeViewModel()
        let a = URL(fileURLWithPath: "/tmp/a.jpg")
        let b = URL(fileURLWithPath: "/tmp/b.png")
        let c = URL(fileURLWithPath: "/tmp/c.heic")

        viewModel.handleImportedImageURLs([a, b], behavior: .append)
        #expect(viewModel.droppedImageURLs == [a, b])

        viewModel.handleImportedImageURLs([b, c], behavior: .append)
        #expect(viewModel.droppedImageURLs == [a, b, c])

        viewModel.handleImportedImageURLs([c, a], behavior: .replace)
        #expect(viewModel.droppedImageURLs == [c, a])
        #expect(viewModel.state == .ready)
    }

    @Test("invalid import moves to failed state")
    @MainActor
    func invalidImportFails() {
        let viewModel = makeViewModel()
        viewModel.handleImportedImageURLs([URL(fileURLWithPath: "/tmp/nope.gif")], behavior: .append)

        if case .failed(let message) = viewModel.state {
            #expect(message.contains("No valid images detected"))
        } else {
            Issue.record("Expected .failed after invalid import")
        }
    }

    @Test("removeImage removes one entry and keeps workflow ready")
    @MainActor
    func removeSingleImage() {
        let viewModel = makeViewModel()
        let a = URL(fileURLWithPath: "/tmp/a.jpg")
        let b = URL(fileURLWithPath: "/tmp/b.jpg")

        viewModel.handleImportedImageURLs([a, b], behavior: .append)
        #expect(viewModel.droppedImageURLs == [a, b])

        viewModel.removeImage(a)

        #expect(viewModel.droppedImageURLs == [b])
        #expect(viewModel.state == .ready)
        #expect(viewModel.hasImportedImages == true)
    }

    @Test("guards update based on state and input")
    @MainActor
    func guardValues() {
        let viewModel = makeViewModel()
        #expect(viewModel.canGenerateModel == false)
        #expect(viewModel.canCancelGeneration == false)
        #expect(viewModel.canClearSelection == false)

        viewModel.handleImportedImageURLs([URL(fileURLWithPath: "/tmp/a.jpg")], behavior: .append)
        #expect(viewModel.canGenerateModel == true)
        #expect(viewModel.canClearSelection == true)
        #expect(viewModel.hasImportedImages == true)
        #expect(viewModel.hasGeneratedPhotogrammetryModel == false)
        #expect(viewModel.outputURL == nil)
    }

    @Test("generation success clamps progress and reaches completed state")
    @MainActor
    func generationSuccess() async {
        let outputURL = URL(fileURLWithPath: "/tmp/success.usdz")
        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService { _, _, onProgress in
                onProgress(-0.5)
                onProgress(1.6)
                try await Task.sleep(nanoseconds: 150_000_000)
                return outputURL
            },
            isPhotogrammetrySupported: { true }
        )
        viewModel.handleImportedImageURLs([URL(fileURLWithPath: "/tmp/a.jpg")], behavior: .append)
        viewModel.generateModel()

        #expect(await waitUntil {
            if case .processing = viewModel.state { return true }
            return false
        })
        #expect(await waitUntil {
            switch viewModel.state {
            case .processing(let progress):
                return progress == 1
            case .completed:
                // CI can transition from processing(1.0) to completed between two polls.
                return true
            default:
                return false
            }
        })

        #expect(await waitUntil {
            if case .completed = viewModel.state { return true }
            return false
        })
        #expect(viewModel.outputURL == outputURL)
        #expect(viewModel.selectedScaleFileURL == outputURL)
        #expect(viewModel.hasGeneratedPhotogrammetryModel == true)
        #expect(viewModel.outputURL != nil)
    }

    @Test("import in high quality starts silent prewarm generation")
    @MainActor
    func importStartsHighPrewarm() async {
        let tracker = ServiceTracker()
        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService(
                tracker: tracker,
                handler: { _, _, _ in
                    try await Task.sleep(nanoseconds: 150_000_000)
                    return URL(fileURLWithPath: "/tmp/prewarm_auto.usdz")
                }
            ),
            isPhotogrammetrySupported: { true }
        )

        viewModel.handleImportedImageURLs([URL(fileURLWithPath: "/tmp/a.jpg")], behavior: .append)

        #expect(await waitUntil {
            if case .ready = viewModel.state { return true }
            return false
        })
        #expect(await waitUntilAsync { await tracker.generateCallCount() == 1 })
        #expect(await tracker.generatedDetailRawValues() == [PhotogrammetrySession.Request.Detail.full.rawValue])
    }

    @Test("generate in high reuses prewarmed result without extra generation")
    @MainActor
    func generateUsesPrewarmedResult() async {
        let tracker = ServiceTracker()
        let outputURL = URL(fileURLWithPath: "/tmp/prewarmed_result.usdz")
        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService(
                tracker: tracker,
                handler: { _, _, _ in
                    try await Task.sleep(nanoseconds: 80_000_000)
                    return outputURL
                }
            ),
            isPhotogrammetrySupported: { true }
        )

        viewModel.handleImportedImageURLs([URL(fileURLWithPath: "/tmp/a.jpg")], behavior: .append)
        #expect(await waitUntilAsync { await tracker.generateCallCount() == 1 })

        try? await Task.sleep(nanoseconds: 150_000_000)
        viewModel.generateModel()

        #expect(await waitUntil {
            if case .completed(let url) = viewModel.state { return url == outputURL }
            return false
        })
        #expect(await tracker.generateCallCount() == 1)
    }

    @Test("generate promotes running prewarm and completes without second generation")
    @MainActor
    func generatePromotesRunningPrewarm() async {
        let tracker = ServiceTracker()
        let outputURL = URL(fileURLWithPath: "/tmp/prewarm_promoted.usdz")
        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService(
                tracker: tracker,
                handler: { _, _, onProgress in
                    onProgress(0.15)
                    try await Task.sleep(nanoseconds: 120_000_000)
                    onProgress(0.70)
                    try await Task.sleep(nanoseconds: 140_000_000)
                    return outputURL
                }
            ),
            isPhotogrammetrySupported: { true }
        )

        viewModel.handleImportedImageURLs([URL(fileURLWithPath: "/tmp/a.jpg")], behavior: .append)
        #expect(await waitUntilAsync { await tracker.generateCallCount() == 1 })

        viewModel.generateModel()

        #expect(await waitUntil {
            if case .processing = viewModel.state { return true }
            return false
        })
        #expect(await waitUntil {
            if case .processing(let progress) = viewModel.state, progress >= 0.7 { return true }
            return false
        })
        #expect(await waitUntil {
            if case .completed(let url) = viewModel.state { return url == outputURL }
            return false
        })
        #expect(await tracker.generateCallCount() == 1)
    }

    @Test("promoted prewarm catches up progress quickly from background state")
    @MainActor
    func promotedPrewarmCatchUpProgress() async {
        let outputURL = URL(fileURLWithPath: "/tmp/prewarm_catchup.usdz")
        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService(
                handler: { _, _, onProgress in
                    onProgress(0.72)
                    try await Task.sleep(nanoseconds: 320_000_000)
                    return outputURL
                }
            ),
            isPhotogrammetrySupported: { true }
        )

        viewModel.handleImportedImageURLs([URL(fileURLWithPath: "/tmp/a.jpg")], behavior: .append)
        try? await Task.sleep(nanoseconds: 50_000_000)

        viewModel.generateModel()

        #expect(await waitUntil {
            if case .processing(let progress) = viewModel.state {
                return progress >= 0.60
            }
            return false
        })
    }

    @Test("switching away from high invalidates prewarm and cleans generated artifact")
    @MainActor
    func qualityChangeInvalidatesPrewarm() async {
        let tracker = ServiceTracker()
        let prewarmOutput = URL(fileURLWithPath: "/tmp/prewarm_for_quality_change.usdz")
        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService(
                tracker: tracker,
                handler: { _, _, _ in prewarmOutput }
            ),
            isPhotogrammetrySupported: { true }
        )

        viewModel.handleImportedImageURLs([URL(fileURLWithPath: "/tmp/a.jpg")], behavior: .append)
        #expect(await waitUntilAsync { await tracker.generateCallCount() == 1 })
        try? await Task.sleep(nanoseconds: 80_000_000)

        viewModel.selectedQuality = .normal

        #expect(await waitUntilAsync { await tracker.cleanedURLs().contains(prewarmOutput) })
    }

    @Test("removing photo invalidates old prewarm and next generate uses classic flow")
    @MainActor
    func removePhotoInvalidatesPrewarmAndGenerateRunsClassicFlow() async {
        let tracker = ServiceTracker()
        let prewarmOutput = URL(fileURLWithPath: "/tmp/prewarm_removed_photo.usdz")
        let classicOutput = URL(fileURLWithPath: "/tmp/classic_after_remove.usdz")
        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService(
                tracker: tracker,
                handler: { _, _, _ in
                    let count = await tracker.generateCallCount()
                    return count <= 1 ? prewarmOutput : classicOutput
                }
            ),
            isPhotogrammetrySupported: { true }
        )

        let a = URL(fileURLWithPath: "/tmp/a.jpg")
        let b = URL(fileURLWithPath: "/tmp/b.jpg")
        viewModel.handleImportedImageURLs([a, b], behavior: .append)
        #expect(await waitUntilAsync { await tracker.generateCallCount() == 1 })
        try? await Task.sleep(nanoseconds: 80_000_000)

        viewModel.removeImage(a)
        #expect(await waitUntilAsync { await tracker.cleanedURLs().contains(prewarmOutput) })
        #expect(await tracker.generateCallCount() == 1)

        viewModel.generateModel()
        #expect(await waitUntil {
            if case .completed(let url) = viewModel.state { return url == classicOutput }
            return false
        })
        #expect(await tracker.generateCallCount() == 2)
    }

    @Test("returning to high after quality change relaunches prewarm")
    @MainActor
    func returnToHighRelaunchesPrewarm() async {
        let tracker = ServiceTracker()
        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService(
                tracker: tracker,
                handler: { _, _, _ in
                    URL(fileURLWithPath: "/tmp/relaunch_\(UUID().uuidString).usdz")
                }
            ),
            isPhotogrammetrySupported: { true }
        )

        viewModel.handleImportedImageURLs([URL(fileURLWithPath: "/tmp/a.jpg")], behavior: .append)
        #expect(await waitUntilAsync { await tracker.generateCallCount() == 1 })
        try? await Task.sleep(nanoseconds: 60_000_000)

        viewModel.selectedQuality = .normal
        viewModel.selectedQuality = .high

        #expect(await waitUntilAsync { await tracker.generateCallCount() == 2 })
    }

    @Test("generate with non-high quality never reuses high prewarm")
    @MainActor
    func nonHighGenerationDoesNotReusePrewarm() async {
        let tracker = ServiceTracker()
        let mediumOutput = URL(fileURLWithPath: "/tmp/medium_generation.usdz")
        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService(
                tracker: tracker,
                handler: { _, detail, _ in
                    return detail == .medium
                        ? mediumOutput
                        : URL(fileURLWithPath: "/tmp/high_prewarm.usdz")
                }
            ),
            isPhotogrammetrySupported: { true }
        )

        viewModel.handleImportedImageURLs([URL(fileURLWithPath: "/tmp/a.jpg")], behavior: .append)
        #expect(await waitUntilAsync { await tracker.generateCallCount() == 1 })
        try? await Task.sleep(nanoseconds: 60_000_000)

        viewModel.selectedQuality = .normal
        viewModel.generateModel()

        #expect(await waitUntil {
            if case .completed(let url) = viewModel.state { return url == mediumOutput }
            return false
        })
        #expect(await tracker.generateCallCount() == 2)
        #expect(await tracker.generatedDetailRawValues() == [
            PhotogrammetrySession.Request.Detail.full.rawValue,
            PhotogrammetrySession.Request.Detail.medium.rawValue,
        ])
    }

    @Test("generation error transitions to failed")
    @MainActor
    func generationFailure() async {
        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService { _, _, _ in throw ViewModelTestError.expectedFailure },
            isPhotogrammetrySupported: { true }
        )
        viewModel.handleImportedImageURLs([URL(fileURLWithPath: "/tmp/a.jpg")], behavior: .append)
        viewModel.generateModel()

        #expect(await waitUntil {
            if case .failed = viewModel.state { return true }
            return false
        })
    }

    @Test("cancelGeneration cancels running task")
    @MainActor
    func cancellation() async {
        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService { _, _, _ in
                while true {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
            },
            isPhotogrammetrySupported: { true }
        )
        viewModel.handleImportedImageURLs([URL(fileURLWithPath: "/tmp/a.jpg")], behavior: .append)
        viewModel.generateModel()

        #expect(await waitUntil {
            if case .processing = viewModel.state { return true }
            return false
        })
        viewModel.cancelGeneration()

        #expect(await waitUntil {
            if case .cancelled = viewModel.state { return true }
            return false
        })
        #expect(viewModel.canCancelGeneration == false)
    }

    @Test("saveGeneratedModel appends extension and removes existing destination")
    @MainActor
    func saveGeneratedModel() throws {
        let fakeFileManager = FakeFileManager()
        let sourceURL = URL(fileURLWithPath: "/tmp/source.usdz")
        let destinationWithoutExtension = URL(fileURLWithPath: "/tmp/output/model")
        fakeFileManager.existingPaths = [destinationWithoutExtension.appendingPathExtension("usdz").path]

        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService { _, _, _ in sourceURL },
            isPhotogrammetrySupported: { true },
            fileManager: fakeFileManager
        )
        viewModel.state = .completed(url: sourceURL)

        try viewModel.saveGeneratedModel(to: destinationWithoutExtension)

        #expect(fakeFileManager.removed == [destinationWithoutExtension.appendingPathExtension("usdz")])
        #expect(fakeFileManager.copies.count == 1)
        #expect(fakeFileManager.copies[0].source == sourceURL)
        #expect(fakeFileManager.copies[0].destination == destinationWithoutExtension.appendingPathExtension("usdz"))
    }

    @Test("scaleModel success updates output and message")
    @MainActor
    func scaleSuccess() async {
        let inputURL = URL(fileURLWithPath: "/tmp/source.usdz")
        let outputURL = URL(fileURLWithPath: "/tmp/scaled_source.usdz")
        let scalingUseCase = StubScalingUseCase { request in
            #expect(request.file == inputURL)
            #expect(request.uncalibrated == 10)
            #expect(request.real == 25)
            return outputURL
        }
        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService { _, _, _ in URL(fileURLWithPath: "/tmp/model.usdz") },
            scalingUseCase: scalingUseCase,
            isPhotogrammetrySupported: { true }
        )
        viewModel.selectedScaleFileURL = inputURL
        viewModel.uncalibratedMeasurement = "10"
        viewModel.realMeasurement = "25"

        viewModel.scaleModel()

        #expect(await waitUntil { viewModel.scalingSuccessCount == 1 })
        #expect(viewModel.outputURL == outputURL)
        #expect(viewModel.selectedScaleFileURL == outputURL)
        #expect(viewModel.scalingResultMessage.contains("Scaled model"))
        #expect(viewModel.isScaling == false)
    }

    @Test("resetting imported images clears scaling progression")
    @MainActor
    func clearingSelectionResetsScalingProgression() async {
        let inputURL = URL(fileURLWithPath: "/tmp/source.usdz")
        let outputURL = URL(fileURLWithPath: "/tmp/scaled_source.usdz")
        let scalingUseCase = StubScalingUseCase { _ in outputURL }

        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService { _, _, _ in URL(fileURLWithPath: "/tmp/model.usdz") },
            scalingUseCase: scalingUseCase,
            isPhotogrammetrySupported: { true }
        )

        viewModel.handleImportedImageURLs([URL(fileURLWithPath: "/tmp/a.jpg")], behavior: .append)
        viewModel.selectedScaleFileURL = inputURL
        viewModel.uncalibratedMeasurement = "10"
        viewModel.realMeasurement = "20"
        viewModel.scaleModel()

        #expect(await waitUntil { viewModel.scalingSuccessCount == 1 })
        #expect(viewModel.scalingSuccessCount == 1)
        #expect(viewModel.outputURL != nil)

        viewModel.clearSelection()

        #expect(viewModel.scalingSuccessCount == 0)
        #expect(viewModel.hasImportedImages == false)
        #expect(viewModel.outputURL == nil)
    }

    @Test("scaleModel failure reports error")
    @MainActor
    func scaleFailure() async {
        let scalingUseCase = StubScalingUseCase { _ in
            throw ViewModelTestError.expectedFailure
        }
        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService { _, _, _ in URL(fileURLWithPath: "/tmp/model.usdz") },
            scalingUseCase: scalingUseCase,
            isPhotogrammetrySupported: { true }
        )
        viewModel.selectedScaleFileURL = URL(fileURLWithPath: "/tmp/source.usdz")
        viewModel.uncalibratedMeasurement = "10"
        viewModel.realMeasurement = "20"

        viewModel.scaleModel()

        #expect(await waitUntil { !viewModel.scalingResultMessage.isEmpty })
        #expect(viewModel.scalingResultMessage.contains("Scaling error"))
        #expect(viewModel.isScaling == false)
    }

    @Test("import failure is centralized by view model")
    @MainActor
    func importFailureHandling() {
        let viewModel = makeViewModel()

        viewModel.handleImportFailure(ViewModelTestError.expectedFailure)

        if case .failed(let message) = viewModel.state {
            #expect(message.contains("Unable to import images"))
            #expect(message.contains("Expected failure"))
        } else {
            Issue.record("Expected failed state after import failure")
        }
    }

    @Test("save failure is centralized by view model")
    @MainActor
    func saveFailureHandling() {
        let viewModel = makeViewModel()

        viewModel.handleSaveFailure(ViewModelTestError.expectedFailure)

        if case .failed(let message) = viewModel.state {
            #expect(message.contains("Unable to save model"))
            #expect(message.contains("Expected failure"))
        } else {
            Issue.record("Expected failed state after save failure")
        }
    }

    @Test("applyMeasuredUncalibratedDistance writes formatted value")
    @MainActor
    func applyMeasuredDistance() {
        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService { _, _, _ in URL(fileURLWithPath: "/tmp/model.usdz") },
            isPhotogrammetrySupported: { true }
        )

        viewModel.applyMeasuredUncalibratedDistance(0.123456789)

        #expect(viewModel.uncalibratedMeasurement == "0.123457")
    }

    @Test("handleMeasurementUpdate updates measurement state and value")
    @MainActor
    func handleMeasurementUpdate() {
        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService { _, _, _ in URL(fileURLWithPath: "/tmp/model.usdz") },
            isPhotogrammetrySupported: { true }
        )

        let update = MeasurementUpdate(
            pointCount: 2,
            distance: 1.25,
            phase: .done
        )
        viewModel.handleMeasurementUpdate(update)

        #expect(viewModel.measurementPhase == .done)
        #expect(viewModel.uncalibratedMeasurement == "1.250000")
    }

    @Test("changing selectedScaleFileURL resets measurement state")
    @MainActor
    func selectedScaleFileReset() {
        let viewModel = PhotogrammetryViewModel(
            service: StubPhotogrammetryService { _, _, _ in URL(fileURLWithPath: "/tmp/model.usdz") },
            isPhotogrammetrySupported: { true }
        )

        viewModel.uncalibratedMeasurement = "2.0"
        viewModel.handleMeasurementUpdate(
            MeasurementUpdate(
                pointCount: 1,
                distance: nil,
                phase: .pickPoint2
            )
        )
        viewModel.selectedScaleFileURL = URL(fileURLWithPath: "/tmp/another.usdz")

        #expect(viewModel.measurementPhase == .idle)
        #expect(viewModel.uncalibratedMeasurement.isEmpty)
    }

    @MainActor
    private func makeViewModel() -> PhotogrammetryViewModel {
        PhotogrammetryViewModel(
            service: StubPhotogrammetryService { _, _, _ in URL(fileURLWithPath: "/tmp/model.usdz") },
            isPhotogrammetrySupported: { true }
        )
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_500_000_000,
        stepNanoseconds: UInt64 = 20_000_000,
        condition: @MainActor @escaping () -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: stepNanoseconds)
        }
        return condition()
    }

    @MainActor
    private func waitUntilAsync(
        timeoutNanoseconds: UInt64 = 1_500_000_000,
        stepNanoseconds: UInt64 = 20_000_000,
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: stepNanoseconds)
        }
        return await condition()
    }
}

private enum ViewModelTestError: LocalizedError {
    case expectedFailure

    var errorDescription: String? { "Expected failure" }
}

private struct StubPhotogrammetryService: PhotogrammetryServicing {
    let tracker: ServiceTracker?
    let handler: @Sendable (
        _ imageURLs: [URL],
        _ detail: PhotogrammetrySession.Request.Detail,
        _ onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL

    init(
        tracker: ServiceTracker? = nil,
        handler: @escaping @Sendable (
            _ imageURLs: [URL],
            _ detail: PhotogrammetrySession.Request.Detail,
            _ onProgress: @escaping @Sendable (Double) -> Void
        ) async throws -> URL
    ) {
        self.tracker = tracker
        self.handler = handler
    }

    func generateUSDZ(from imageURLs: [URL], detail: PhotogrammetrySession.Request.Detail) async throws -> URL {
        await tracker?.recordGenerateCall(detailRawValue: detail.rawValue)
        return try await handler(imageURLs, detail, { _ in })
    }

    func generateUSDZ(
        from imageURLs: [URL],
        detail: PhotogrammetrySession.Request.Detail,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        await tracker?.recordGenerateCall(detailRawValue: detail.rawValue)
        return try await handler(imageURLs, detail, onProgress)
    }

    func cleanupGeneratedModel(at outputURL: URL) {
        Task {
            await tracker?.recordCleanupCall(url: outputURL)
        }
    }
}

private actor ServiceTracker {
    private var generateCalls = 0
    private var detailRawValues: [Int] = []
    private var cleaned: [URL] = []

    func recordGenerateCall(detailRawValue: Int) {
        generateCalls += 1
        detailRawValues.append(detailRawValue)
    }

    func recordCleanupCall(url: URL) {
        cleaned.append(url)
    }

    func generateCallCount() -> Int {
        generateCalls
    }

    func generatedDetailRawValues() -> [Int] {
        detailRawValues
    }

    func cleanedURLs() -> [URL] {
        cleaned
    }
}

private struct StubScalingUseCase: ScalingUseCase {
    let scaleHandler: @Sendable (ScalingRequest) throws -> URL

    func makeRequest(file: URL?, uncalibrated: String, real: String, overwrite: Bool) throws -> ScalingRequest {
        guard let file else {
            throw ScalingError.invalidInput("Missing file")
        }

        guard let uncalibratedValue = Double(uncalibrated),
              let realValue = Double(real) else {
            throw ScalingError.invalidInput("Invalid values")
        }

        return ScalingRequest(
            file: file,
            uncalibrated: uncalibratedValue,
            real: realValue,
            overwrite: overwrite
        )
    }

    func execute(_ request: ScalingRequest) async throws -> URL {
        try scaleHandler(request)
    }
}

private final class FakeFileManager: FileManaging {
    var existingPaths: Set<String> = []
    var removed: [URL] = []
    var copies: [(source: URL, destination: URL)] = []

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }

    func removeItem(at url: URL) throws {
        removed.append(url)
        existingPaths.remove(url.path)
    }

    func copyItem(at srcURL: URL, to dstURL: URL) throws {
        copies.append((srcURL, dstURL))
        existingPaths.insert(dstURL.path)
    }
}
