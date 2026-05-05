import Foundation
import Testing
@testable import EasyPhotogrammetry

@Suite("SupportedImageFormat")
struct SupportedImageFormatTests {
    @Test("accepts supported extensions including uppercase")
    func supportsKnownFormats() {
        #expect(SupportedImageFormat.isSupported(URL(fileURLWithPath: "/tmp/a.jpg")))
        #expect(SupportedImageFormat.isSupported(URL(fileURLWithPath: "/tmp/a.JPEG")))
        #expect(SupportedImageFormat.isSupported(URL(fileURLWithPath: "/tmp/a.PNG")))
        #expect(SupportedImageFormat.isSupported(URL(fileURLWithPath: "/tmp/a.heic")))
        #expect(SupportedImageFormat.isSupported(URL(fileURLWithPath: "/tmp/a.tif")))
        #expect(SupportedImageFormat.isSupported(URL(fileURLWithPath: "/tmp/a.tiff")))
    }

    @Test("rejects unsupported extensions")
    func rejectsUnknownFormats() {
        #expect(!SupportedImageFormat.isSupported(URL(fileURLWithPath: "/tmp/a.gif")))
        #expect(!SupportedImageFormat.isSupported(URL(fileURLWithPath: "/tmp/a.pdf")))
        #expect(!SupportedImageFormat.isSupported(URL(fileURLWithPath: "/tmp/a")))
    }

    @Test("user-facing list stays coherent")
    func userFacingList() {
        #expect(SupportedImageFormat.userFacingList == "jpg, jpeg, png, heic, tiff")
    }
}
