import Foundation
import RealityKit

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
        let inputDirectory = fm.temporaryDirectory
            .appendingPathComponent("Baguette_Input_\(UUID().uuidString)", isDirectory: true)
        let outputDirectory = fm.temporaryDirectory
            .appendingPathComponent("Baguette_Output_\(UUID().uuidString)", isDirectory: true)

        try fm.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for imageURL in validImages {
            let destination = inputDirectory.appendingPathComponent(imageURL.lastPathComponent)
            if fm.fileExists(atPath: destination.path) {
                let deduplicatedName = "\(UUID().uuidString)_\(imageURL.lastPathComponent)"
                try fm.copyItem(at: imageURL, to: inputDirectory.appendingPathComponent(deduplicatedName))
            } else {
                try fm.copyItem(at: imageURL, to: destination)
            }
        }

        let outputURL = outputDirectory.appendingPathComponent("Model.usdz")

        let config = PhotogrammetrySession.Configuration()
        let session = try PhotogrammetrySession(input: inputDirectory, configuration: config)
        let request = PhotogrammetrySession.Request.modelFile(url: outputURL, detail: detail)

        try session.process(requests: [request])

        for try await output in session.outputs {
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

        guard fm.fileExists(atPath: outputURL.path) else {
            throw PhotogrammetryServiceError.outputNotFound(outputURL)
        }

        return outputURL
    }
}
