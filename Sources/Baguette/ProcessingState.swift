import Foundation

enum ProcessingState: Equatable {
    case idle
    case ready
    case processing(progress: Double)
    case cancelled
    case completed(url: URL)
    case failed(message: String)

    var statusText: String {
        switch self {
        case .idle:
            return "Drop photos to start"
        case .ready:
            return "Ready to generate the model"
        case .processing:
            return "Processing..."
        case .cancelled:
            return "Generation cancelled"
        case .completed:
            return "Model generated"
        case .failed(let message):
            return message
        }
    }

    var progressValue: Double {
        switch self {
        case .processing(let progress):
            return progress
        default:
            return 0
        }
    }

    var presentation: StatusPresentation {
        switch self {
        case .idle:
            return StatusPresentation(
                title: "Ready",
                detail: nil,
                symbolName: "circle",
                tone: .secondary,
                progress: nil
            )
        case .ready:
            return StatusPresentation(
                title: "Ready to generate",
                detail: nil,
                symbolName: "checkmark.circle",
                tone: .secondary,
                progress: nil
            )
        case .processing(let progress):
            return StatusPresentation(
                title: "Generating model",
                detail: nil,
                symbolName: "gearshape.2",
                tone: .secondary,
                progress: progress,
                progressText: "\(Int(progress * 100))%"
            )
        case .cancelled:
            return StatusPresentation(
                title: "Generation cancelled",
                detail: nil,
                symbolName: "xmark.circle.fill",
                tone: .secondary,
                progress: nil
            )
        case .completed:
            return StatusPresentation(
                title: "Model generated",
                detail: nil,
                symbolName: "checkmark.circle.fill",
                tone: .success,
                progress: nil
            )
        case .failed(let message):
            return StatusPresentation(
                title: "Generation failed",
                detail: message,
                symbolName: "exclamationmark.triangle.fill",
                tone: .error,
                progress: nil
            )
        }
    }
}

struct StatusPresentation: Equatable {
    enum Tone: Equatable {
        case secondary
        case success
        case error
    }

    let title: String
    let detail: String?
    let symbolName: String
    let tone: Tone
    let progress: Double?
    let progressText: String?

    init(
        title: String,
        detail: String?,
        symbolName: String,
        tone: Tone,
        progress: Double?,
        progressText: String? = nil
    ) {
        self.title = title
        self.detail = detail
        self.symbolName = symbolName
        self.tone = tone
        self.progress = progress
        self.progressText = progressText
    }
}
