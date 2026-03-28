import Foundation

/// Centralized list of image formats accepted by the import pipeline.
enum SupportedImageFormat {
    private static let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff", "tif"]

    static var userFacingList: String {
        "jpg, jpeg, png, heic, tiff"
    }

    static func isSupported(_ url: URL) -> Bool {
        allowedExtensions.contains(url.pathExtension.lowercased())
    }
}
