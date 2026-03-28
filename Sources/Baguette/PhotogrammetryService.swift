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

enum PhotogrammetryServiceError: LocalizedError {
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
    private let temporaryStore: TemporaryGenerationStore

    init(temporaryStore: TemporaryGenerationStore = .shared) {
        self.temporaryStore = temporaryStore
    }

    func generateUSDZ(from imageURLs: [URL], detail: PhotogrammetrySession.Request.Detail) async throws -> URL {
        try await generateUSDZ(from: imageURLs, detail: detail, onProgress: { _ in })
    }

    func generateUSDZ(
        from imageURLs: [URL],
        detail: PhotogrammetrySession.Request.Detail,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard PhotogrammetrySession.isSupported else {
            throw PhotogrammetryServiceError.unsupportedDevice
        }

        let validImages = imageURLs.filter(SupportedImageFormat.isSupported)
        guard !validImages.isEmpty else {
            throw PhotogrammetryServiceError.noValidImages
        }

        let fm = FileManager.default
        let workspace = try temporaryStore.createWorkspace()
        let inputDirectory = workspace.inputDirectory
        let outputURL = workspace.outputModelURL

        for imageURL in validImages {
            let destination = inputDirectory.appendingPathComponent(imageURL.lastPathComponent)
            if fm.fileExists(atPath: destination.path) {
                let deduplicatedName = "\(UUID().uuidString)_\(imageURL.lastPathComponent)"
                try fm.copyItem(at: imageURL, to: inputDirectory.appendingPathComponent(deduplicatedName))
            } else {
                try fm.copyItem(at: imageURL, to: destination)
            }
        }

        let config = PhotogrammetrySession.Configuration()
        let session = try PhotogrammetrySession(input: inputDirectory, configuration: config)
        return try await withTaskCancellationHandler {
            defer { temporaryStore.removeInputDirectoryIfPresent(at: inputDirectory) }

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
                    guard fm.fileExists(atPath: outputURL.path) else {
                        throw PhotogrammetryServiceError.outputNotFound(outputURL)
                    }
                    return outputURL
                default:
                    break
                }
            }

            try Task.checkCancellation()

            guard fm.fileExists(atPath: outputURL.path) else {
                throw PhotogrammetryServiceError.outputNotFound(outputURL)
            }

            return outputURL
        } onCancel: {
            session.cancel()
        }
    }
}

final class TemporaryGenerationStore: @unchecked Sendable {
    static let shared = TemporaryGenerationStore()

    struct Workspace {
        let inputDirectory: URL
        let outputDirectory: URL
        let outputModelURL: URL
    }

    private let fileManager = FileManager.default
    private let lock = NSLock()
    private let rootDirectory: URL

    private init() {
        rootDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("Baguette_Generated_Models", isDirectory: true)

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
