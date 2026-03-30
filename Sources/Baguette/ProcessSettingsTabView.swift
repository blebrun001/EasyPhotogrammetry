import SwiftUI

struct ProcessSettingsTabView: View {
    @ObservedObject var viewModel: PhotogrammetryViewModel

    var body: some View {
        VStack(spacing: 12) {
            Form {
                Section("Configuration") {
                    configurationSection
                }

                Section("Status") {
                    statusSection
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: .infinity)

            HStack {
                Spacer()
                actionButton
                Spacer()
            }
        }
        .padding(16)
    }

    private var configurationSection: some View {
        LabeledContent("Quality") {
            Picker("Quality", selection: $viewModel.selectedQuality) {
                ForEach(ModelQuality.allCases) { quality in
                    Text(quality.label)
                        .tag(quality)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .disabled(!viewModel.canImportImages)
            .help("Choose model quality before generation.")
        }
    }

    private var statusSection: some View {
        let presentation = viewModel.state.presentation

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let symbolName = presentation.symbolName {
                    Image(systemName: symbolName)
                        .foregroundStyle(color(for: presentation.tone))
                }

                Text(presentation.title)
                    .font(.headline)
            }

            if let detail = presentation.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let progress = presentation.progress {
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .controlSize(.small)

                    if let progressText = presentation.progressText {
                        Text(progressText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Processing Status")
        .accessibilityValue(presentation.title)
        .help("Current generation state, including progress and latest details.")
    }

    private var actionButton: some View {
        Group {
            if viewModel.canCancelGeneration {
                Button(role: .destructive) {
                    viewModel.cancelGeneration()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .keyboardShortcut(.cancelAction)
                .help("Stop the current model generation.")
                .accessibilityLabel("Stop Generation")
                .accessibilityHint("Cancel the 3D model generation in progress")
            } else {
                Button {
                    viewModel.generateModel()
                } label: {
                    Text("Generate")
                        .frame(minWidth: 140)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canGenerateModel)
                .help("Generate a USDZ model from the selected photos.")
                .accessibilityLabel("Generate Model")
                .accessibilityHint("Run Apple Object Capture with selected images")
            }
        }
        .controlSize(.large)
    }

    private func color(for tone: StatusPresentation.Tone) -> Color {
        switch tone {
        case .secondary:
            return .secondary
        case .success:
            return .green
        case .error:
            return .red
        }
    }
}
