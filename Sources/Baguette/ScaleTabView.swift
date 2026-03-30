import SwiftUI

struct ScaleTabView: View {
    @ObservedObject var viewModel: PhotogrammetryViewModel
    @State private var isMeasurementModeEnabled = false
    @State private var editingCommand: MeasurementEditingCommand = .none
    @State private var editingCommandToken = UUID()
    @State private var measurementUpdate: MeasurementUpdate = .idle

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button(measurementButtonTitle) {
                        handleMeasurementButtonTap()
                    }
                    .disabled(viewModel.selectedScaleFileURL == nil)
                    .help(measurementButtonHelpText)

                    Spacer()
                }

                SurfaceMeasurementView(
                    modelURL: viewModel.selectedScaleFileURL,
                    isMeasurementModeEnabled: isMeasurementModeEnabled,
                    editingCommand: editingCommand,
                    editingCommandToken: editingCommandToken
                ) { update in
                    measurementUpdate = update
                    viewModel.handleMeasurementUpdate(update)
                    viewModel.scalingResultMessage = ""

                    if update.phase == .done {
                        isMeasurementModeEnabled = false
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help(measurementSurfaceHelpText)

                TextField("Real measurement (cm)", text: $viewModel.realMeasurement)
                    .textFieldStyle(.roundedBorder)
                    .help("Enter the real-world distance in centimeters (for example: 12.5).")

                if !viewModel.scalingResultMessage.isEmpty {
                    Text(viewModel.scalingResultMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .help("Latest scaling output or error message.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Spacer()
                actionButton
                Spacer()
            }
        }
        .padding(16)
        .onChange(of: viewModel.selectedScaleFileURL) { _, _ in
            resetMeasurementUI()
        }
    }

    private var actionButton: some View {
        Button {
            viewModel.scaleModel()
        } label: {
            Text("Start scaling")
                .frame(minWidth: 140)
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .tint(isUncalibratedMeasurementMissing ? .gray : .accentColor)
        .disabled(!viewModel.canScaleModel || isUncalibratedMeasurementMissing)
        .controlSize(.large)
        .help(scaleButtonHelpText)
    }

    private var isUncalibratedMeasurementMissing: Bool {
        viewModel.uncalibratedMeasurement
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var measurementButtonTitle: String {
        if measurementUpdate.pointCount >= 2 {
            return "Restart scaling"
        }

        if measurementUpdate.pointCount == 1 {
            return "Select point 2"
        }

        return isMeasurementModeEnabled ? "Select point 1" : "Start measure"
    }

    private var measurementButtonHelpText: String {
        if measurementUpdate.pointCount >= 2 {
            return "Clear current points and start a new distance measurement."
        }

        if measurementUpdate.pointCount == 1 {
            return "Click on the model to place the second point."
        }

        return "Enable measurement mode, then click on the model to place the first point."
    }

    private var measurementSurfaceHelpText: String {
        if isMeasurementModeEnabled {
            return "Click two points on the model to measure a distance."
        }

        return "Click Start measure to pick points. Click the model to toggle wireframe view."
    }

    private var scaleButtonHelpText: String {
        if isUncalibratedMeasurementMissing {
            return "Measure the model first to set the uncalibrated distance."
        }

        return "Scale the model using measured distance and real-world centimeters."
    }

    private func handleMeasurementButtonTap() {
        if measurementUpdate.pointCount >= 2 {
            restartScalingSelection()
            return
        }

        isMeasurementModeEnabled = true
        sendEditingCommand(.none)
    }

    private func sendEditingCommand(_ command: MeasurementEditingCommand) {
        editingCommand = command
        editingCommandToken = UUID()
    }

    private func restartScalingSelection() {
        isMeasurementModeEnabled = true
        measurementUpdate = .idle
        sendEditingCommand(.reset)
        viewModel.resetMeasurementState(clearUncalibrated: true)
        viewModel.scalingResultMessage = ""
    }

    private func resetMeasurementUI() {
        isMeasurementModeEnabled = false
        measurementUpdate = .idle
        sendEditingCommand(.reset)
        viewModel.resetMeasurementState(clearUncalibrated: true)
    }
}
