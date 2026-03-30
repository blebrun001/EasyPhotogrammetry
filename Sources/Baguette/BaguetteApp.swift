import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        TemporaryGenerationStore.shared.cleanupAll()
    }
}

@main
struct BaguetteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = PhotogrammetryViewModel(service: PhotogrammetryService())

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 900, height: 680)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Baguette") {
                    showAboutPanel()
                }
            }
        }
    }

    private func showAboutPanel() {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Baguette"
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let versionString = shortVersion == buildVersion ? shortVersion : "\(shortVersion) (\(buildVersion))"
        let copyright = "Copyright (C) 2026 Brice Lebrun"
        let credits = NSAttributedString(
            string: """
            Licensed under the GNU General Public License v3.0.
            See LICENSE at the root of this project.
            """
        )

        NSApp.orderFrontStandardAboutPanel(
            options: [
                .applicationName: appName,
                .version: versionString,
                .copyright: copyright,
                .credits: credits,
            ]
        )
        NSApp.activate(ignoringOtherApps: true)
    }
}

private extension NSApplication.AboutPanelOptionKey {
    static let copyright = NSApplication.AboutPanelOptionKey(rawValue: "Copyright")
}
