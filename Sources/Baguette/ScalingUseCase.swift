import Foundation

struct ScalingRequest {
    let file: URL
    let uncalibrated: Double
    let real: Double
    let overwrite: Bool
}

protocol ScalingUseCase {
    func makeRequest(file: URL?, uncalibrated: String, real: String, overwrite: Bool) throws -> ScalingRequest
    func execute(_ request: ScalingRequest) throws -> URL
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

        guard let realValue = Double(real),
              let uncalibratedValue = Double(uncalibrated),
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

    func execute(_ request: ScalingRequest) throws -> URL {
        try scaler.scaleUSDZ(
            file: request.file,
            uncalibrated: request.uncalibrated,
            real: request.real,
            overwrite: request.overwrite
        )
    }
}
