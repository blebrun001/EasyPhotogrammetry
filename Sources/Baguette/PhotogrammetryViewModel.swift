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
            return "Aperçu (rapide)"
        case .reduced:
            return "Réduite"
        case .medium:
            return "Moyenne"
        case .full:
            return "Élevée"
        case .raw:
            return "Brute (max)"
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

    private let service: PhotogrammetryServicing

    init(service: PhotogrammetryServicing) {
        self.service = service

        if !PhotogrammetrySession.isSupported {
            state = .failed(message: "Cette machine n'est pas compatible avec la photogrammétrie Apple.")
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

    var imageCountText: String {
        "\(droppedImageURLs.count) photo(s) sélectionnée(s)"
    }

    var compactImageCountText: String {
        "\(droppedImageURLs.count) img"
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
                state = .failed(message: "Aucune image valide détectée (\(SupportedImageFormat.userFacingList)).")
                return
            }

            droppedImageURLs = Self.uniquePreservingOrder(accepted)
            state = .ready
        }

        return true
    }

    func generateModel() async {
        guard canGenerateModel else { return }

        state = .processing(progress: 0)

        do {
            let outputURL = try await service.generateUSDZ(
                from: droppedImageURLs,
                detail: selectedQuality.detail,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        guard let self else { return }
                        self.state = .processing(progress: Self.clampProgress(progress))
                    }
                }
            )
            state = .completed(url: outputURL)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    private static func clampProgress(_ value: Double) -> Double {
        min(1, max(0, value))
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
