import AppKit
import Foundation

enum AppIconBootstrap {
    @MainActor
    static func apply() {
        guard
            let iconURL = Bundle.module.url(forResource: "Baguette", withExtension: "icns"),
            let icon = NSImage(contentsOf: iconURL)
        else {
            return
        }

        NSApplication.shared.applicationIconImage = icon
    }
}
