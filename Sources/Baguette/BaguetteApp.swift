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
    }
}
