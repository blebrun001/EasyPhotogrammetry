import Foundation

struct ScalingRequest {
    let file: URL
    let uncalibrated: Double
    let real: Double
}

protocol ScalingUseCase: Sendable {
    func makeRequest(file: URL?, uncalibrated: String, real: String) throws -> ScalingRequest
    func execute(_ request: ScalingRequest) async throws -> URL
}

struct DefaultScalingUseCase: ScalingUseCase {
    private let scaler: USDZScaling

    init(scaler: USDZScaling = USDZScaler()) {
        self.scaler = scaler
    }

    func makeRequest(file: URL?, uncalibrated: String, real: String) throws -> ScalingRequest {
        guard let file else {
            throw ScalingError.invalidInput("Please select a USDZ file.")
        }

        guard let realValue = Double(real),
              let uncalibratedValue = Double(uncalibrated),
              realValue > 0,
              uncalibratedValue > 0 else {
            throw ScalingError.invalidInput("Please provide valid positive numeric values for both measurements.")
        }

        return ScalingRequest(
            file: file,
            uncalibrated: uncalibratedValue,
            real: realValue
        )
    }

    func execute(_ request: ScalingRequest) async throws -> URL {
        let scaler = SendableScalerBox(scaler: scaler)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let url = try scaler.scaler.scaleUSDZ(
                        file: request.file,
                        uncalibrated: request.uncalibrated,
                        real: request.real
                    )
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private struct SendableScalerBox: @unchecked Sendable {
    let scaler: USDZScaling
}
