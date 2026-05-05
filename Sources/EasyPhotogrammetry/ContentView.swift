import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Top-level tab container coordinating navigation between import, process, and scale flows.
struct ContentView: View {
    @ObservedObject var viewModel: PhotogrammetryViewModel
    @State private var selectedTab: AppTab = .importPhotos

    var body: some View {
        TabView(selection: $selectedTab) {
            ImportPhotosTabView(viewModel: viewModel)
                .tabItem {
                    tabLabel("Import", systemImage: "photo.on.rectangle", isEnabled: true)
                }
                .tag(AppTab.importPhotos)

            ProcessSettingsTabView(viewModel: viewModel)
                .tabItem {
                    tabLabel("Process", systemImage: "slider.horizontal.3", isEnabled: canAccessProcess)
                }
                .tag(AppTab.process)
                .disabled(!canAccessProcess)

            ScaleTabView(viewModel: viewModel)
                .tabItem {
                    tabLabel("Scale", systemImage: "ruler", isEnabled: canAccessScale)
                }
                .tag(AppTab.scale)
                .disabled(!canAccessScale)
        }
        .overlay(alignment: .top) {
            if let feedback = viewModel.ephemeralFeedback {
                EphemeralFeedbackBanner(
                    message: feedback.message,
                    onDismiss: { viewModel.clearEphemeralFeedback() }
                )
                .padding(.top, 12)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: viewModel.ephemeralFeedback?.id)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    guard let outputURL = viewModel.outputURL else { return }
                    presentSavePanel(for: outputURL)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(!canShareModel)
                .help("Export the latest generated model as a USDZ file.")
                .accessibilityLabel("Share")
            }
        }
        .onAppear {
            selectedTab = enforceTabAccess(for: selectedTab)
        }
        .onChange(of: selectedTab) { _, newTab in
            let accessibleTab = enforceTabAccess(for: newTab)
            guard accessibleTab == newTab else {
                selectedTab = accessibleTab
                return
            }
        }
        .onChange(of: canAccessProcess) { _, _ in
            selectedTab = enforceTabAccess(for: selectedTab)
        }
        .onChange(of: canAccessScale) { _, _ in
            selectedTab = enforceTabAccess(for: selectedTab)
        }
    }

    private var canAccessProcess: Bool {
        viewModel.hasImportedImages
    }

    private var canAccessScale: Bool {
        viewModel.hasGeneratedPhotogrammetryModel
    }

    private var canShareModel: Bool {
        viewModel.outputURL != nil
    }

    /// Builds a tab label that visually reflects enabled/disabled accessibility state.
    /// - Parameters:
    ///   - title: Tab title.
    ///   - systemImage: SF Symbol identifier.
    ///   - isEnabled: Whether the tab is currently accessible.
    /// - Returns: Styled tab label view.
    @ViewBuilder
    private func tabLabel(_ title: String, systemImage: String, isEnabled: Bool) -> some View {
        Label {
            Text(title)
                .foregroundColor(isEnabled ? .primary : .gray)
        } icon: {
            Image(systemName: systemImage)
                .foregroundColor(isEnabled ? .primary : .gray)
        }
    }

    /// Redirects a requested tab to the nearest accessible tab based on current app state.
    /// - Parameter requestedTab: Tab requested by the user.
    /// - Returns: Effective tab that can be displayed.
    private func enforceTabAccess(for requestedTab: AppTab) -> AppTab {
        switch requestedTab {
        case .importPhotos:
            return .importPhotos
        case .process:
            return canAccessProcess ? .process : .importPhotos
        case .scale:
            if canAccessScale { return .scale }
            if canAccessProcess { return .process }
            return .importPhotos
        }
    }

    /// Presents a save panel and delegates file export to the view model.
    /// - Parameter outputURL: Latest generated output used to seed the default directory.
    private func presentSavePanel(for outputURL: URL) {
        let panel = NSSavePanel()
        if let usdzType = UTType(filenameExtension: "usdz") {
            panel.allowedContentTypes = [usdzType]
        }
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Model.usdz"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? outputURL.deletingLastPathComponent()

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        do {
            try viewModel.saveGeneratedModel(to: destinationURL)
        } catch {
            viewModel.handleSaveFailure(error)
        }
    }
}

/// Temporary top banner used to display transient success/status feedback.
private struct EphemeralFeedbackBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text(message)
                .font(.subheadline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss this message.")
            .accessibilityLabel("Dismiss message")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

/// Main application tabs.
enum AppTab: Hashable {
    case importPhotos
    case process
    case scale
}
