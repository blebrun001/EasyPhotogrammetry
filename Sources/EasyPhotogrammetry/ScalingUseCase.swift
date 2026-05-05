import Foundation

/// Normalized input consumed by the scaler implementation.
struct ScalingRequest {
    let file: URL
    let uncalibrated: Double
    let real: Double
    let overwrite: Bool
}

/// Builds and executes validated scaling requests.
protocol ScalingUseCase: Sendable {
    /// Validates raw user inputs and converts them into a canonical scaling request.
    /// - Parameters:
    ///   - file: Target USDZ file selected in the UI.
    ///   - uncalibrated: Measured distance on the unscaled model, as user text.
    ///   - real: Real-world distance that the measured segment should match, as user text.
    ///   - overwrite: Whether the output should replace the input file.
    /// - Returns: A validated `ScalingRequest`.
    /// - Throws: `ScalingError.invalidInput` when values are missing or non-positive.
    func makeRequest(file: URL?, uncalibrated: String, real: String, overwrite: Bool) throws -> ScalingRequest
    /// Executes scaling asynchronously to avoid blocking the main actor.
    /// - Parameter request: Validated request produced by `makeRequest`.
    /// - Returns: URL of the written scaled USDZ file.
    /// - Throws: Any scaling or I/O error produced by `USDZScaling`.
    func execute(_ request: ScalingRequest) async throws -> URL
}

/// Default app use case that validates values and delegates geometry work to `USDZScaling`.
struct DefaultScalingUseCase: ScalingUseCase {
    private let scaler: USDZScaling

    /// - Parameter scaler: Injectable scaling backend used by tests and production.
    init(scaler: USDZScaling = USDZScaler()) {
        self.scaler = scaler
    }

    /// Validates the selected file and parses user-entered measurements.
    /// - Parameters:
    ///   - file: Optional model URL selected by the user.
    ///   - uncalibrated: Uncalibrated measurement text.
    ///   - real: Real-world measurement text.
    ///   - overwrite: Whether the destination should reuse the original file path.
    /// - Returns: A request ready to be executed by the scaler backend.
    /// - Throws: `ScalingError.invalidInput` when file or numeric values are invalid.
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

    /// Executes scaling on a background queue and bridges the callback into async/await.
    /// - Parameter request: Validated scaling request.
    /// - Returns: URL of the generated scaled file.
    /// - Throws: Any error thrown by the underlying `USDZScaling` implementation.
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

    /// Parses a decimal value from user text while accepting locale and comma decimal separators.
    /// - Parameter rawValue: Raw user input from a text field.
    /// - Returns: Parsed decimal value or `nil` when parsing fails.
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

/// Lightweight wrapper used to move non-Sendable scaler dependencies across concurrency boundaries.
private struct SendableScalerBox: @unchecked Sendable {
    let scaler: USDZScaling
}
