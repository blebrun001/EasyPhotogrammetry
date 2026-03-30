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

                TextField("Calibrated measure (cm)", text: $viewModel.realMeasurement)
                    .textFieldStyle(.roundedBorder)

                if !viewModel.scalingResultMessage.isEmpty {
                    Text(viewModel.scalingResultMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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
