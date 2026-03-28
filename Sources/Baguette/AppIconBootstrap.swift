import AppKit
import Foundation

enum AppIconBootstrap {
    @MainActor
    static func apply() {
        var candidateBundles: [Bundle] = [.main]
        #if SWIFT_PACKAGE
            candidateBundles.append(.module)
        #endif

        for bundle in candidateBundles {
            if
                let iconURL = bundle.url(forResource: "Baguette", withExtension: "icns"),
                let icon = NSImage(contentsOf: iconURL)
            {
                NSApplication.shared.applicationIconImage = icon
                return
            }
        }
    }
}
