import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            AppIconBootstrap.apply()
        }
    }
}

@main
struct BaguetteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: PhotogrammetryViewModel(service: PhotogrammetryService()))
                .frame(minWidth: 720, minHeight: 520)
        }
    }
}
