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
        if case .processing(let progress) = viewModel.state {
            #expect(progress == 1)
        } else {
            Issue.record("Expected processing state before completion")
        }

        #expect(await waitUntil {
            if case .completed = viewModel.state { return true }
            return false
        })
        #expect(viewModel.outputURL == outputURL)
        #expect(viewModel.selectedScaleFileURL == outputURL)
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
    func scaleSuccess() {
        let inputURL = URL(fileURLWithPath: "/tmp/source.usdz")
        let outputURL = URL(fileURLWithPath: "/tmp/scaled_source.usdz")
        let scalingUseCase = StubScalingUseCase { request in
            #expect(request.file == inputURL)
            #expect(request.uncalibrated == 10)
            #expect(request.real == 25)
            #expect(request.overwrite == false)
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
        viewModel.overwriteScaledModel = false

        viewModel.scaleModel()

        #expect(viewModel.outputURL == outputURL)
        #expect(viewModel.selectedScaleFileURL == outputURL)
        #expect(viewModel.scalingResultMessage.contains("Scaled model"))
        #expect(viewModel.isScaling == false)
    }

    @Test("scaleModel failure reports error")
    @MainActor
    func scaleFailure() {
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

        #expect(viewModel.scalingResultMessage.contains("Scaling error"))
        #expect(viewModel.isScaling == false)
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
}

private enum ViewModelTestError: LocalizedError {
    case expectedFailure

    var errorDescription: String? { "Expected failure" }
}

private struct StubPhotogrammetryService: PhotogrammetryServicing {
    let handler: @Sendable (
        _ imageURLs: [URL],
        _ detail: PhotogrammetrySession.Request.Detail,
        _ onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL

    func generateUSDZ(from imageURLs: [URL], detail: PhotogrammetrySession.Request.Detail) async throws -> URL {
        try await handler(imageURLs, detail, { _ in })
    }

    func generateUSDZ(
        from imageURLs: [URL],
        detail: PhotogrammetrySession.Request.Detail,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await handler(imageURLs, detail, onProgress)
    }
}

private struct StubScalingUseCase: ScalingUseCase {
    let scaleHandler: (ScalingRequest) throws -> URL

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

    func execute(_ request: ScalingRequest) throws -> URL {
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
