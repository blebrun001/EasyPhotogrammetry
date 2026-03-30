import AppKit
import SwiftUI

/// App delegate used for lifecycle cleanup of temporary generation artifacts.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Cleans temporary photogrammetry workspaces when the app exits.
    /// - Parameter notification: Standard termination notification from AppKit.
    func applicationWillTerminate(_ notification: Notification) {
        TemporaryGenerationStore.shared.cleanupAll()
    }
}

@main
/// Main SwiftUI entry point for Baguette.
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

    /// Displays a custom About panel with license and version details.
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

/// Custom key used to expose copyright text in the About panel.
private extension NSApplication.AboutPanelOptionKey {
    static let copyright = NSApplication.AboutPanelOptionKey(rawValue: "Copyright")
}
