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
            return "Glissez des photos pour commencer"
        case .ready:
            return "Prêt à générer le modèle"
        case .processing:
            return "Traitement en cours..."
        case .completed:
            return "Modèle généré"
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
