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
/// Main SwiftUI entry point for EasyPhotogrammetry.
struct EasyPhotogrammetryApp: App {
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
                Button("About EasyPhotogrammetry") {
                    showAboutPanel()
                }
            }
        }
    }

    /// Displays a custom About panel with license and version details.
    private func showAboutPanel() {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "EasyPhotogrammetry"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let madeBy = "Made by Brice Lebrun - IPHES-CERCA"
        let githubURL = URL(string: "https://github.com/blebrun001/EasyPhotogrammetry")!
        let centeredParagraphStyle = NSMutableParagraphStyle()
        centeredParagraphStyle.alignment = .center
        let credits = NSMutableAttributedString(
            string: "License: GNU General Public License v3.0 (GPL-3.0).\n\n",
            attributes: [.paragraphStyle: centeredParagraphStyle]
        )
        credits.append(
            NSAttributedString(
                string: "GitHub Repository",
                attributes: [
                    .paragraphStyle: centeredParagraphStyle,
                    .link: githubURL,
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ]
            )
        )

        NSApp.orderFrontStandardAboutPanel(
            options: [
                .applicationName: appName,
                .version: buildVersion,
                .copyright: madeBy,
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
