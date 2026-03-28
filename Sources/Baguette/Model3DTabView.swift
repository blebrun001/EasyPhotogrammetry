import QuickLookUI
import SwiftUI

struct Model3DTabView: View {
    let modelURL: URL?
    let instanceID: UUID
    let onSaveModel: (URL) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                QuickLookModelPreview(url: modelURL)
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

private struct QuickLookModelPreview: NSViewRepresentable {
    let url: URL?

    final class Coordinator {
        var currentURL: URL?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> QLPreviewView {
        QLPreviewView(frame: .zero, style: .normal)
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        guard let url else {
            context.coordinator.currentURL = nil
            nsView.previewItem = nil
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            context.coordinator.currentURL = nil
            nsView.previewItem = nil
            return
        }

        let shouldUpdatePreviewItem = context.coordinator.currentURL != url || nsView.previewItem == nil
        if shouldUpdatePreviewItem {
            context.coordinator.currentURL = url
            nsView.previewItem = url as NSURL
            nsView.refreshPreviewItem()
        }
    }

    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: Coordinator) {
        coordinator.currentURL = nil
        nsView.previewItem = nil
    }
}
