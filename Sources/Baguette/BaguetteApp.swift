import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            AppIconBootstrap.apply()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        TemporaryGenerationStore.shared.cleanupAll()
    }
}

@main
struct BaguetteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: PhotogrammetryViewModel(service: PhotogrammetryService()))
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 900, height: 680)
    }
}
