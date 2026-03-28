import SwiftUI

@main
struct BaguetteApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: PhotogrammetryViewModel(service: PhotogrammetryService()))
                .frame(minWidth: 720, minHeight: 520)
        }
    }
}
