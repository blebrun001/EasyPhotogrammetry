import Foundation
import Testing
@testable import Baguette

@Suite("ScalingUseCase")
struct ScalingUseCaseTests {
    @Test("makeRequest throws when file is missing")
    func missingFile() {
        let useCase = DefaultScalingUseCase(scaler: SpyScaler())

        #expect(throws: ScalingError.self) {
            _ = try useCase.makeRequest(file: nil, uncalibrated: "10", real: "20")
        }
    }

    @Test("makeRequest throws on non numeric or non positive inputs")
    func invalidNumbers() {
        let useCase = DefaultScalingUseCase(scaler: SpyScaler())
        let file = URL(fileURLWithPath: "/tmp/model.usdz")

        #expect(throws: ScalingError.self) {
            _ = try useCase.makeRequest(file: file, uncalibrated: "abc", real: "20")
        }
        #expect(throws: ScalingError.self) {
            _ = try useCase.makeRequest(file: file, uncalibrated: "10", real: "0")
        }
    }

    @Test("makeRequest builds a valid request")
    func validRequest() throws {
        let useCase = DefaultScalingUseCase(scaler: SpyScaler())
        let file = URL(fileURLWithPath: "/tmp/model.usdz")

        let request = try useCase.makeRequest(file: file, uncalibrated: "12.5", real: "25")

        #expect(request.file == file)
        #expect(request.uncalibrated == 12.5)
        #expect(request.real == 25)
    }
}

private struct SpyScaler: USDZScaling {
    func scaleUSDZ(file: URL, uncalibrated: Double, real: Double) throws -> URL {
        file
    }
}
