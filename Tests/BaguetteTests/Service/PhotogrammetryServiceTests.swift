import Foundation
import RealityKit
import Testing
@testable import Baguette

@Suite("PhotogrammetryService")
struct PhotogrammetryServiceTests {
    @Test("throws unsupported device when machine is not compatible")
    func unsupportedDevice() async {
        let service = PhotogrammetryService(
            temporaryStore: TemporaryGenerationStore(rootDirectory: try! TestFilesystem.makeTempDirectory(prefix: "svc-unsupported"), cleanOnInit: true),
            isPhotogrammetrySupported: { false }
        )

        do {
            _ = try await service.generateUSDZ(from: [URL(fileURLWithPath: "/tmp/a.jpg")], detail: .preview)
            Issue.record("Expected unsupportedDevice error")
        } catch let error as PhotogrammetryServiceError {
            #expect(error == .unsupportedDevice)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("throws noValidImages when all files are unsupported")
    func noValidImages() async {
        let service = PhotogrammetryService(
            temporaryStore: TemporaryGenerationStore(rootDirectory: try! TestFilesystem.makeTempDirectory(prefix: "svc-invalid"), cleanOnInit: true),
            isPhotogrammetrySupported: { true }
        )

        do {
            _ = try await service.generateUSDZ(
                from: [
                    URL(fileURLWithPath: "/tmp/a.gif"),
                    URL(fileURLWithPath: "/tmp/a.txt")
                ],
                detail: .full
            )
            Issue.record("Expected noValidImages error")
        } catch let error as PhotogrammetryServiceError {
            #expect(error == .noValidImages)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("stages files, deduplicates file names, and cleans input directory")
    func stagesAndCleansInputDirectory() async throws {
        let testRoot = try TestFilesystem.makeTempDirectory(prefix: "svc-stage")
        defer { TestFilesystem.removeIfPresent(testRoot) }

        let sourceA = testRoot.appendingPathComponent("sourceA", isDirectory: true)
        let sourceB = testRoot.appendingPathComponent("sourceB", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceB, withIntermediateDirectories: true)

        let fileA = sourceA.appendingPathComponent("same-name.jpg")
        let fileB = sourceB.appendingPathComponent("same-name.jpg")
        try TestFilesystem.writeFile(fileA, contents: "a")
        try TestFilesystem.writeFile(fileB, contents: "b")

        let recorder = ServiceRunRecorder()
        let store = TemporaryGenerationStore(rootDirectory: testRoot.appendingPathComponent("store", isDirectory: true), cleanOnInit: true)
        let service = PhotogrammetryService(
            temporaryStore: store,
            isPhotogrammetrySupported: { true },
            sessionRunner: { inputDirectory, outputURL, _, _ in
                let fileNames = try FileManager.default.contentsOfDirectory(atPath: inputDirectory.path)
                await recorder.record(inputDirectory: inputDirectory, fileNames: fileNames)
                try Data("ok".utf8).write(to: outputURL)
            }
        )

        let outputURL = try await service.generateUSDZ(from: [fileA, fileB], detail: .medium)
        let snapshot = await recorder.snapshot()

        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        #expect(snapshot.fileNames.count == 2)
        #expect(snapshot.fileNames.contains("same-name.jpg"))
        #expect(snapshot.fileNames.contains(where: { $0.hasSuffix("_same-name.jpg") }))
        #expect(!FileManager.default.fileExists(atPath: snapshot.inputDirectory.path))
    }

    @Test("throws outputNotFound if runner does not produce model")
    func outputNotFound() async throws {
        let testRoot = try TestFilesystem.makeTempDirectory(prefix: "svc-missing-output")
        defer { TestFilesystem.removeIfPresent(testRoot) }
        let source = testRoot.appendingPathComponent("image.jpg")
        try TestFilesystem.writeFile(source)

        let service = PhotogrammetryService(
            temporaryStore: TemporaryGenerationStore(rootDirectory: testRoot.appendingPathComponent("store", isDirectory: true), cleanOnInit: true),
            isPhotogrammetrySupported: { true },
            sessionRunner: { _, _, _, _ in }
        )

        do {
            _ = try await service.generateUSDZ(from: [source], detail: .preview)
            Issue.record("Expected outputNotFound error")
        } catch let error as PhotogrammetryServiceError {
            guard case .outputNotFound = error else {
                Issue.record("Expected outputNotFound, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("propagates runner errors and forwards progress updates")
    func runnerErrorAndProgress() async throws {
        let testRoot = try TestFilesystem.makeTempDirectory(prefix: "svc-progress")
        defer { TestFilesystem.removeIfPresent(testRoot) }

        let source = testRoot.appendingPathComponent("image.jpg")
        try TestFilesystem.writeFile(source)

        let progressRecorder = ProgressRecorder()
        let service = PhotogrammetryService(
            temporaryStore: TemporaryGenerationStore(rootDirectory: testRoot.appendingPathComponent("store", isDirectory: true), cleanOnInit: true),
            isPhotogrammetrySupported: { true },
            sessionRunner: { _, outputURL, _, onProgress in
                onProgress(0.25)
                onProgress(0.75)
                await progressRecorder.record(0.25)
                await progressRecorder.record(0.75)
                throw ServiceTestError.expectedRunnerFailure(outputURL)
            }
        )

        do {
            _ = try await service.generateUSDZ(
                from: [source],
                detail: .reduced,
                onProgress: { value in
                    Task { await progressRecorder.record(value) }
                }
            )
            Issue.record("Expected expectedRunnerFailure")
        } catch let error as ServiceTestError {
            guard case .expectedRunnerFailure = error else {
                Issue.record("Unexpected ServiceTestError: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let values = await progressRecorder.values()
        #expect(values.contains(0.25))
        #expect(values.contains(0.75))
    }
}

private enum ServiceTestError: Error {
    case expectedRunnerFailure(URL)
}

private actor ServiceRunRecorder {
    private var inputDirectory: URL = URL(fileURLWithPath: "/tmp/unknown")
    private var fileNames: [String] = []

    func record(inputDirectory: URL, fileNames: [String]) {
        self.inputDirectory = inputDirectory
        self.fileNames = fileNames
    }

    func snapshot() -> (inputDirectory: URL, fileNames: [String]) {
        (inputDirectory, fileNames)
    }
}

private actor ProgressRecorder {
    private var captured: [Double] = []

    func record(_ value: Double) {
        captured.append(value)
    }

    func values() -> [Double] {
        captured
    }
}
