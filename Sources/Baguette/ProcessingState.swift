import Foundation

enum ProcessingState: Equatable {
    case idle
    case ready
    case processing(progress: Double)
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
}
