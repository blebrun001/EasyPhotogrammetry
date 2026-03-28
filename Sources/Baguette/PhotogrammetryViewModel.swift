import Foundation
import RealityKit
import UniformTypeIdentifiers

enum ModelQuality: String, CaseIterable, Identifiable {
    case preview
    case reduced
    case medium
    case full
    case raw

    var id: String { rawValue }

    var label: String {
        switch self {
        case .preview:
            return "Preview (fast)"
        case .reduced:
            return "Reduced"
        case .medium:
            return "Medium"
        case .full:
            return "High"
        case .raw:
            return "Raw (max)"
        }
    }

    var shortLabel: String {
        switch self {
        case .preview:
            return "Preview"
        case .reduced:
            return "Reduced"
        case .medium:
            return "Medium"
        case .full:
            return "Full"
        case .raw:
            return "Raw"
        }
    }

    var detail: PhotogrammetrySession.Request.Detail {
        switch self {
        case .preview:
            return .preview
        case .reduced:
            return .reduced
        case .medium:
            return .medium
        case .full:
            return .full
        case .raw:
            return .raw
        }
    }
}

/// Main UI state holder for drag-and-drop and model generation flow.
@MainActor
final class PhotogrammetryViewModel: ObservableObject {
    @Published private(set) var droppedImageURLs: [URL] = []
    @Published var state: ProcessingState = .idle
    @Published var isDropTargeted = false
    @Published var selectedQuality: ModelQuality = .full
    @Published var isImportPickerPresented = false

    private let service: PhotogrammetryServicing
    private var generationTask: Task<Void, Never>?

    init(service: PhotogrammetryServicing) {
        self.service = service

        if !PhotogrammetrySession.isSupported {
            state = .failed(message: "This machine is not compatible with Apple photogrammetry.")
        }
    }

    var canGenerateModel: Bool {
        guard PhotogrammetrySession.isSupported else { return false }
        guard !droppedImageURLs.isEmpty else { return false }

        if case .processing = state {
            return false
        }

        return true
    }

    var canCancelGeneration: Bool {
        if case .processing = state {
            return true
        }
        return false
    }

    var canImportImages: Bool {
        guard PhotogrammetrySession.isSupported else { return false }
        if case .processing = state {
            return false
        }
        return true
    }

    var canClearSelection: Bool {
        !droppedImageURLs.isEmpty && canImportImages
    }

    var outputURL: URL? {
        if case .completed(let url) = state {
            return url
        }
        return nil
    }

    var canSaveGeneratedModel: Bool {
        outputURL != nil
    }

    var hasGeneratedModel: Bool {
        outputURL != nil
    }

    func handleDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        Task { @MainActor in
            var accepted: [URL] = []

            for provider in providers {
                guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                    continue
                }

                do {
                    let url = try await provider.loadFileURL()
                    if SupportedImageFormat.isSupported(url) {
                        accepted.append(url)
                    }
                } catch {
                    continue
                }
            }

            if accepted.isEmpty {
                state = .failed(message: "No valid images detected (\(SupportedImageFormat.userFacingList)).")
                return
            }

            setImages(accepted, behavior: .replace)
        }

        return true
    }

    func presentImportPicker() {
        guard canImportImages else { return }
        isImportPickerPresented = true
    }

    func handleImportedImageURLs(_ urls: [URL], behavior: ImportBehavior = .append) {
        guard canImportImages else { return }
        setImages(urls, behavior: behavior)
    }

    func clearSelection() {
        guard canClearSelection else { return }
        generationTask?.cancel()
        generationTask = nil
        droppedImageURLs = []
        state = .idle
    }

    func generateModel() {
        guard canGenerateModel else { return }
        generationTask?.cancel()
        generationTask = Task { [weak self] in
            await self?.runGeneration()
        }
    }

    func cancelGeneration() {
        guard canCancelGeneration else { return }
        generationTask?.cancel()
        generationTask = nil
        state = .cancelled
    }

    func saveGeneratedModel(to destinationURL: URL) throws {
        guard let sourceURL = outputURL else { return }

        let finalDestination: URL
        if destinationURL.pathExtension.isEmpty {
            finalDestination = destinationURL.appendingPathExtension("usdz")
        } else {
            finalDestination = destinationURL
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: finalDestination.path) {
            try fileManager.removeItem(at: finalDestination)
        }
        try fileManager.copyItem(at: sourceURL, to: finalDestination)
    }

    private func runGeneration() async {
        guard !Task.isCancelled else { return }

        state = .processing(progress: 0)

        do {
            let outputURL = try await service.generateUSDZ(
                from: droppedImageURLs,
                detail: selectedQuality.detail,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        guard let self else { return }
                        guard !Task.isCancelled else { return }
                        self.state = .processing(progress: Self.clampProgress(progress))
                    }
                }
            )
            guard !Task.isCancelled else {
                state = .cancelled
                generationTask = nil
                return
            }
            state = .completed(url: outputURL)
        } catch is CancellationError {
            state = .cancelled
        } catch {
            state = .failed(message: error.localizedDescription)
        }

        generationTask = nil
    }

    private static func clampProgress(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private func setImages(_ urls: [URL], behavior: ImportBehavior) {
        let filtered = urls.filter(SupportedImageFormat.isSupported)
        guard !filtered.isEmpty else {
            state = .failed(message: "No valid images detected (\(SupportedImageFormat.userFacingList)).")
            return
        }

        let merged: [URL]
        switch behavior {
        case .replace:
            merged = filtered
        case .append:
            merged = droppedImageURLs + filtered
        }

        droppedImageURLs = Self.uniquePreservingOrder(merged)
        state = .ready
    }

    private static func uniquePreservingOrder(_ urls: [URL]) -> [URL] {
        var seen: Set<URL> = []
        var result: [URL] = []

        for url in urls where seen.insert(url).inserted {
            result.append(url)
        }

        return result
    }
}

enum ImportBehavior {
    case append
    case replace
}

private extension NSItemProvider {
    func loadFileURL() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }

                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                continuation.resume(throwing: CocoaError(.fileReadCorruptFile))
            }
        }
    }
}
