import Foundation

/// Centralized list of image formats accepted by the import pipeline.
enum SupportedImageFormat {
    /// File extensions accepted by drag-and-drop and file import flows.
    private static let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff", "tif"]

    /// Human-readable list used in validation feedback.
    static var userFacingList: String {
        "jpg, jpeg, png, heic, tiff"
    }

    /// Returns `true` when the file extension is part of the supported image set.
    /// - Parameter url: Candidate image URL selected by the user.
    /// - Returns: `true` if the extension is accepted by the ingestion pipeline.
    static func isSupported(_ url: URL) -> Bool {
        allowedExtensions.contains(url.pathExtension.lowercased())
    }
}
