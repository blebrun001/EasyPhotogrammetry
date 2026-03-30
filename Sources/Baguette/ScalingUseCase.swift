import Foundation

struct ScalingRequest {
    let file: URL
    let uncalibrated: Double
    let real: Double
    let overwrite: Bool
}

protocol ScalingUseCase: Sendable {
    func makeRequest(file: URL?, uncalibrated: String, real: String, overwrite: Bool) throws -> ScalingRequest
    func execute(_ request: ScalingRequest) async throws -> URL
}

struct DefaultScalingUseCase: ScalingUseCase {
    private let scaler: USDZScaling

    init(scaler: USDZScaling = USDZScaler()) {
        self.scaler = scaler
    }

    func makeRequest(file: URL?, uncalibrated: String, real: String, overwrite: Bool) throws -> ScalingRequest {
        guard let file else {
            throw ScalingError.invalidInput("Please select a USDZ file.")
        }

        guard let realValue = Self.parseMeasurementValue(real),
              let uncalibratedValue = Self.parseMeasurementValue(uncalibrated),
              realValue > 0,
              uncalibratedValue > 0 else {
            throw ScalingError.invalidInput("Please provide valid positive numeric values for both measurements.")
        }

        return ScalingRequest(
            file: file,
            uncalibrated: uncalibratedValue,
            real: realValue,
            overwrite: overwrite
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
                        real: request.real,
                        overwrite: request.overwrite
                    )
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func parseMeasurementValue(_ rawValue: String) -> Double? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let value = Double(trimmed) {
            return value
        }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        if let value = Double(normalized) {
            return value
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        return formatter.number(from: trimmed)?.doubleValue
    }
}

private struct SendableScalerBox: @unchecked Sendable {
    let scaler: USDZScaling
}
