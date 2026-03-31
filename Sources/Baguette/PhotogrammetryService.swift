import Foundation
@preconcurrency import RealityKit

/// Abstraction used by the view model to generate a USDZ model from image files.
protocol PhotogrammetryServicing: Sendable {
    /// Generates a USDZ model from user-provided photos.
    /// - Parameters:
    ///   - imageURLs: Candidate image file URLs.
    ///   - detail: Output quality level for Object Capture.
    /// - Returns: URL of the generated USDZ model.
    /// - Throws: `PhotogrammetryServiceError` or underlying runtime errors.
    func generateUSDZ(from imageURLs: [URL], detail: PhotogrammetrySession.Request.Detail) async throws -> URL
    /// Generates a USDZ model while reporting progress updates in `[0, 1]`.
    /// - Parameters:
    ///   - imageURLs: Candidate image file URLs.
    ///   - detail: Output quality level for Object Capture.
    ///   - onProgress: Callback invoked with request progress updates.
    /// - Returns: URL of the generated USDZ model.
    /// - Throws: `PhotogrammetryServiceError` or underlying runtime errors.
    func generateUSDZ(
        from imageURLs: [URL],
        detail: PhotogrammetrySession.Request.Detail,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL
    /// Generates a USDZ model with explicit photogrammetry configuration options.
    /// - Parameters:
    ///   - imageURLs: Candidate image file URLs.
    ///   - detail: Output quality level for Object Capture.
    ///   - featureSensitivity: Feature sensitivity used by Object Capture.
    ///   - isObjectMaskingEnabled: Whether object masking is enabled.
    ///   - onProgress: Callback invoked with request progress updates.
    /// - Returns: URL of the generated USDZ model.
    /// - Throws: `PhotogrammetryServiceError` or underlying runtime errors.
    func generateUSDZ(
        from imageURLs: [URL],
        detail: PhotogrammetrySession.Request.Detail,
        featureSensitivity: PhotogrammetrySession.Configuration.FeatureSensitivity,
        isObjectMaskingEnabled: Bool,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL
    /// Removes temporary workspace artifacts associated with a previously generated model.
    /// - Parameter outputURL: Model URL returned by `generateUSDZ`.
    func cleanupGeneratedModel(at outputURL: URL)
}

/// Injected runner used to execute RealityKit sessions, primarily for testability.
typealias PhotogrammetrySessionRunner = @Sendable (
    _ inputDirectory: URL,
    _ outputURL: URL,
    _ detail: PhotogrammetrySession.Request.Detail,
    _ featureSensitivity: PhotogrammetrySession.Configuration.FeatureSensitivity,
    _ isObjectMaskingEnabled: Bool,
    _ onProgress: @escaping @Sendable (Double) -> Void
) async throws -> Void

/// Errors specific to photogrammetry orchestration.
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
    private static let defaultSessionRunner: PhotogrammetrySessionRunner = { inputDirectory, outputURL, detail, featureSensitivity, isObjectMaskingEnabled, onProgress in
        try await runRealityKitSession(
            inputDirectory: inputDirectory,
            outputURL: outputURL,
            detail: detail,
            featureSensitivity: featureSensitivity,
            isObjectMaskingEnabled: isObjectMaskingEnabled,
            onProgress: onProgress
        )
    }

    private let temporaryStore: TemporaryGenerationStore
    private let isPhotogrammetrySupported: @Sendable () -> Bool
    private let sessionRunner: PhotogrammetrySessionRunner
    private let fileManager: FileManager
    private let stagingQueue: DispatchQueue

    /// - Parameters:
    ///   - temporaryStore: Workspace manager used for isolated generation folders.
    ///   - isPhotogrammetrySupported: Capability check, injectable for tests.
    ///   - sessionRunner: RealityKit execution closure.
    ///   - fileManager: File system dependency.
    ///   - stagingQueue: Serial queue used to stage input files.
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

    /// Convenience overload that ignores progress updates.
    /// - Parameters:
    ///   - imageURLs: Candidate image URLs.
    ///   - detail: Requested Object Capture detail level.
    /// - Returns: URL of the generated USDZ file.
    /// - Throws: `PhotogrammetryServiceError` or session errors.
    func generateUSDZ(from imageURLs: [URL], detail: PhotogrammetrySession.Request.Detail) async throws -> URL {
        try await generateUSDZ(
            from: imageURLs,
            detail: detail,
            featureSensitivity: .normal,
            isObjectMaskingEnabled: false,
            onProgress: { _ in }
        )
    }

    /// Validates images, stages them into an isolated workspace, runs Object Capture, and returns output URL.
    /// - Parameters:
    ///   - imageURLs: Candidate image URLs.
    ///   - detail: Requested Object Capture detail level.
    ///   - onProgress: Callback receiving progress updates in `[0, 1]`.
    /// - Returns: URL of the generated USDZ file.
    /// - Throws: `PhotogrammetryServiceError` when unsupported, input is empty, or output is missing.
    func generateUSDZ(
        from imageURLs: [URL],
        detail: PhotogrammetrySession.Request.Detail,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await generateUSDZ(
            from: imageURLs,
            detail: detail,
            featureSensitivity: .normal,
            isObjectMaskingEnabled: false,
            onProgress: onProgress
        )
    }

    /// Validates images, stages them into an isolated workspace, runs Object Capture, and returns output URL.
    /// - Parameters:
    ///   - imageURLs: Candidate image URLs.
    ///   - detail: Requested Object Capture detail level.
    ///   - featureSensitivity: Feature sensitivity used by Object Capture.
    ///   - isObjectMaskingEnabled: Whether object masking is enabled.
    ///   - onProgress: Callback receiving progress updates in `[0, 1]`.
    /// - Returns: URL of the generated USDZ file.
    /// - Throws: `PhotogrammetryServiceError` when unsupported, input is empty, or output is missing.
    func generateUSDZ(
        from imageURLs: [URL],
        detail: PhotogrammetrySession.Request.Detail,
        featureSensitivity: PhotogrammetrySession.Configuration.FeatureSensitivity,
        isObjectMaskingEnabled: Bool,
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

        try await sessionRunner(inputDirectory, outputURL, detail, featureSensitivity, isObjectMaskingEnabled, onProgress)

        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw PhotogrammetryServiceError.outputNotFound(outputURL)
        }

        return outputURL
    }

    /// Removes the workspace containing the provided generated model.
    /// - Parameter outputURL: Previously generated model URL.
    func cleanupGeneratedModel(at outputURL: URL) {
        temporaryStore.removeWorkspace(containingOutputModelAt: outputURL)
    }

    /// Copies validated images into the session input directory.
    /// Duplicate file names are deduplicated with UUID prefixes to keep all inputs.
    /// - Parameters:
    ///   - imageURLs: Valid source image URLs.
    ///   - inputDirectory: Destination staging directory.
    /// - Throws: Any file-copying error.
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

    /// Runs a RealityKit Object Capture session and forwards progress updates.
    /// - Parameters:
    ///   - inputDirectory: Staged input image directory.
    ///   - outputURL: Destination USDZ file URL.
    ///   - detail: Requested model detail.
    ///   - onProgress: Progress callback.
    /// - Throws: Cancellation or session processing errors.
    private static func runRealityKitSession(
        inputDirectory: URL,
        outputURL: URL,
        detail: PhotogrammetrySession.Request.Detail,
        featureSensitivity: PhotogrammetrySession.Configuration.FeatureSensitivity,
        isObjectMaskingEnabled: Bool,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        var config = PhotogrammetrySession.Configuration()
        config.featureSensitivity = featureSensitivity
        config.isObjectMaskingEnabled = isObjectMaskingEnabled
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

/// Wrapper that marks `FileManager` as Sendable for controlled cross-actor usage.
private struct SendableFileManagerBox: @unchecked Sendable {
    let fileManager: FileManager
}

/// Manages isolated temporary folders for generation sessions and cleanup.
final class TemporaryGenerationStore: @unchecked Sendable {
    static let shared = TemporaryGenerationStore()

    /// File-system layout reserved for one generation run.
    struct Workspace {
        let inputDirectory: URL
        let outputDirectory: URL
        let outputModelURL: URL
    }

    private let fileManager: FileManager
    private let lock = NSLock()
    private let rootDirectory: URL

    /// - Parameters:
    ///   - rootDirectory: Optional custom root for workspaces (defaults to system temporary directory).
    ///   - fileManager: File-system dependency.
    ///   - cleanOnInit: Whether to remove stale root data during initialization.
    init(rootDirectory: URL? = nil, fileManager: FileManager = .default, cleanOnInit: Bool = true) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? fileManager.temporaryDirectory
            .appendingPathComponent("Baguette_Generated_Models", isDirectory: true)

        guard cleanOnInit else { return }
        prepareRootDirectory()
    }

    /// Recreates the root directory and removes stale data from previous runs.
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

    /// Creates an isolated workspace with input/output subdirectories.
    /// - Returns: Fresh workspace unique to the current generation call.
    /// - Throws: File-system creation errors.
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

    /// Removes the input directory after generation to keep only the produced model.
    /// - Parameter inputDirectory: Input directory created by `createWorkspace`.
    func removeInputDirectoryIfPresent(at inputDirectory: URL) {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: inputDirectory)
    }

    /// Removes the entire temporary root directory tree.
    func cleanupAll() {
        lock.lock()
        defer { lock.unlock() }

        guard fileManager.fileExists(atPath: rootDirectory.path) else {
            return
        }

        try? fileManager.removeItem(at: rootDirectory)
    }

    /// Removes the session directory containing a generated model URL.
    /// - Parameter outputModelURL: Output model URL returned by the service.
    func removeWorkspace(containingOutputModelAt outputModelURL: URL) {
        lock.lock()
        defer { lock.unlock() }

        let sessionDirectory = outputModelURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
        let root = rootDirectory.standardizedFileURL

        guard sessionDirectory.pathComponents.starts(with: root.pathComponents) else {
            return
        }

        guard fileManager.fileExists(atPath: sessionDirectory.path) else {
            return
        }

        try? fileManager.removeItem(at: sessionDirectory)
    }
}
