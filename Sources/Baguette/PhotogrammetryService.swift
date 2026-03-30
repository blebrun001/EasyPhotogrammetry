import Foundation
@preconcurrency import RealityKit

/// Abstraction used by the view model to generate a USDZ model from image files.
protocol PhotogrammetryServicing: Sendable {
    func generateUSDZ(from imageURLs: [URL], detail: PhotogrammetrySession.Request.Detail) async throws -> URL
    func generateUSDZ(
        from imageURLs: [URL],
        detail: PhotogrammetrySession.Request.Detail,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL
}

typealias PhotogrammetrySessionRunner = @Sendable (
    _ inputDirectory: URL,
    _ outputURL: URL,
    _ detail: PhotogrammetrySession.Request.Detail,
    _ onProgress: @escaping @Sendable (Double) -> Void
) async throws -> Void

enum PhotogrammetryServiceError: LocalizedError, Equatable {
    case unsupportedDevice
    case noValidImages
    case outputNotFound(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedDevice:
            return "This machine does not support PhotogrammetrySession."
        case .noValidImages:
            return "No valid images to process."
        case .outputNotFound(let url):
            return "The USDZ model was not generated: \(url.path)."
        }
    }
}

/// Concrete RealityKit-backed implementation for Apple Object Capture.
final class PhotogrammetryService: PhotogrammetryServicing, @unchecked Sendable {
    private static let defaultSessionRunner: PhotogrammetrySessionRunner = { inputDirectory, outputURL, detail, onProgress in
        try await runRealityKitSession(
            inputDirectory: inputDirectory,
            outputURL: outputURL,
            detail: detail,
            onProgress: onProgress
        )
    }

    private let temporaryStore: TemporaryGenerationStore
    private let isPhotogrammetrySupported: @Sendable () -> Bool
    private let sessionRunner: PhotogrammetrySessionRunner
    private let fileManager: FileManager
    private let stagingQueue: DispatchQueue

    init(
        temporaryStore: TemporaryGenerationStore = .shared,
        isPhotogrammetrySupported: @escaping @Sendable () -> Bool = { PhotogrammetrySession.isSupported },
        sessionRunner: @escaping PhotogrammetrySessionRunner = PhotogrammetryService.defaultSessionRunner,
        fileManager: FileManager = .default,
        stagingQueue: DispatchQueue = DispatchQueue(label: "Baguette.PhotogrammetryService.Staging", qos: .userInitiated)
    ) {
        self.temporaryStore = temporaryStore
        self.isPhotogrammetrySupported = isPhotogrammetrySupported
        self.sessionRunner = sessionRunner
        self.fileManager = fileManager
        self.stagingQueue = stagingQueue
    }

    func generateUSDZ(from imageURLs: [URL], detail: PhotogrammetrySession.Request.Detail) async throws -> URL {
        try await generateUSDZ(from: imageURLs, detail: detail, onProgress: { _ in })
    }

    func generateUSDZ(
        from imageURLs: [URL],
        detail: PhotogrammetrySession.Request.Detail,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard isPhotogrammetrySupported() else {
            throw PhotogrammetryServiceError.unsupportedDevice
        }

        let validImages = imageURLs.filter(SupportedImageFormat.isSupported)
        guard !validImages.isEmpty else {
            throw PhotogrammetryServiceError.noValidImages
        }

        let workspace = try temporaryStore.createWorkspace()
        let inputDirectory = workspace.inputDirectory
        let outputURL = workspace.outputModelURL

        try await stageImages(validImages, in: inputDirectory)

        defer { temporaryStore.removeInputDirectoryIfPresent(at: inputDirectory) }

        try await sessionRunner(inputDirectory, outputURL, detail, onProgress)

        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw PhotogrammetryServiceError.outputNotFound(outputURL)
        }

        return outputURL
    }

    private func stageImages(_ imageURLs: [URL], in inputDirectory: URL) async throws {
        let fileManager = SendableFileManagerBox(fileManager: self.fileManager)
        try await withCheckedThrowingContinuation { continuation in
            stagingQueue.async {
                do {
                    for imageURL in imageURLs {
                        let destination = inputDirectory.appendingPathComponent(imageURL.lastPathComponent)
                        if fileManager.fileManager.fileExists(atPath: destination.path) {
                            let deduplicatedName = "\(UUID().uuidString)_\(imageURL.lastPathComponent)"
                            try fileManager.fileManager.copyItem(at: imageURL, to: inputDirectory.appendingPathComponent(deduplicatedName))
                        } else {
                            try fileManager.fileManager.copyItem(at: imageURL, to: destination)
                        }
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runRealityKitSession(
        inputDirectory: URL,
        outputURL: URL,
        detail: PhotogrammetrySession.Request.Detail,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let config = PhotogrammetrySession.Configuration()
        let session = try PhotogrammetrySession(input: inputDirectory, configuration: config)

        try await withTaskCancellationHandler {
            try Task.checkCancellation()

            let request = PhotogrammetrySession.Request.modelFile(url: outputURL, detail: detail)
            try session.process(requests: [request])

            for try await output in session.outputs {
                try Task.checkCancellation()

                switch output {
                case .requestProgress(_, let fractionComplete):
                    onProgress(fractionComplete)
                case .requestError(_, let error):
                    throw error
                case .processingComplete:
                    return
                default:
                    break
                }
            }

            try Task.checkCancellation()
        } onCancel: {
            session.cancel()
        }
    }
}

private struct SendableFileManagerBox: @unchecked Sendable {
    let fileManager: FileManager
}

final class TemporaryGenerationStore: @unchecked Sendable {
    static let shared = TemporaryGenerationStore()

    struct Workspace {
        let inputDirectory: URL
        let outputDirectory: URL
        let outputModelURL: URL
    }

    private let fileManager: FileManager
    private let lock = NSLock()
    private let rootDirectory: URL

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default, cleanOnInit: Bool = true) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? fileManager.temporaryDirectory
            .appendingPathComponent("Baguette_Generated_Models", isDirectory: true)

        guard cleanOnInit else { return }
        prepareRootDirectory()
    }

    private func prepareRootDirectory() {
        do {
            if fileManager.fileExists(atPath: rootDirectory.path) {
                try fileManager.removeItem(at: rootDirectory)
            }
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        } catch {
            // The app can still run without pre-cleaning old temporary data.
        }
    }

    func createWorkspace() throws -> Workspace {
        lock.lock()
        defer { lock.unlock() }

        let sessionDirectory = rootDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let inputDirectory = sessionDirectory.appendingPathComponent("input", isDirectory: true)
        let outputDirectory = sessionDirectory.appendingPathComponent("output", isDirectory: true)
        let outputModelURL = outputDirectory.appendingPathComponent("\(UUID().uuidString).usdz")

        try fileManager.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        return Workspace(
            inputDirectory: inputDirectory,
            outputDirectory: outputDirectory,
            outputModelURL: outputModelURL
        )
    }

    func removeInputDirectoryIfPresent(at inputDirectory: URL) {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: inputDirectory)
    }

    func cleanupAll() {
        lock.lock()
        defer { lock.unlock() }

        guard fileManager.fileExists(atPath: rootDirectory.path) else {
            return
        }

        try? fileManager.removeItem(at: rootDirectory)
    }
}
