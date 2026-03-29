import SceneKit
import SwiftUI

struct Model3DTabView: View {
    let modelURL: URL?
    let instanceID: UUID
    let onSaveModel: (URL) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                SceneKitModelPreview(url: modelURL)
                    .id(instanceID)

                if modelURL == nil {
                    unavailablePlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let modelURL {
                Button {
                    onSaveModel(modelURL)
                } label: {
                    Label("Save…", systemImage: "square.and.arrow.down")
                }
                .help("Save the generated model with a custom name")
                .accessibilityLabel("Save Model")
                .accessibilityHint("Choose where to save the generated USDZ model")
            }
        }
        .padding(16)
    }

    private var unavailablePlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("No 3D model available yet")
                .font(.headline)
            Text("Generate a model from the Photos tab.")
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct SceneKitModelPreview: NSViewRepresentable {
    let url: URL?

    final class Coordinator {
        var currentURL: URL?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .windowBackgroundColor
        view.scene = SCNScene()
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        guard context.coordinator.currentURL != url else { return }

        context.coordinator.currentURL = url

        guard let url else {
            nsView.scene = SCNScene()
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            nsView.scene = SCNScene()
            return
        }

        do {
            nsView.scene = try SCNScene(url: url, options: nil)
        } catch {
            nsView.scene = SCNScene()
        }
    }

    static func dismantleNSView(_ nsView: SCNView, coordinator: Coordinator) {
        coordinator.currentURL = nil
        nsView.scene = nil
    }
}
