import Foundation
import SceneKit
import Testing
@testable import Baguette

@Suite("USDZScaler")
struct USDZScalerTests {
    @Test("throws fileNotFound when input is missing")
    func missingInput() {
        let scaler = USDZScaler()

        #expect(throws: ScalingError.self) {
            _ = try scaler.scaleUSDZ(
                file: URL(fileURLWithPath: "/tmp/does-not-exist.usdz"),
                uncalibrated: 10,
                real: 20,
                overwrite: true
            )
        }
    }

    @Test("creates scaled_ file when overwrite is false")
    func createsScaledFile() throws {
        let testRoot = try TestFilesystem.makeTempDirectory(prefix: "scale-new")
        defer { TestFilesystem.removeIfPresent(testRoot) }

        let input = testRoot.appendingPathComponent("model.usdz")
        try makeSampleUSDZ(at: input)

        let scaler = USDZScaler()
        let output = try scaler.scaleUSDZ(file: input, uncalibrated: 10, real: 25, overwrite: false)

        #expect(output.lastPathComponent == "scaled_model.usdz")
        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    @Test("overwrite writes result to source path")
    func overwriteSource() throws {
        let testRoot = try TestFilesystem.makeTempDirectory(prefix: "scale-overwrite")
        defer { TestFilesystem.removeIfPresent(testRoot) }

        let input = testRoot.appendingPathComponent("model.usdz")
        try makeSampleUSDZ(at: input)

        let scaler = USDZScaler()
        let output = try scaler.scaleUSDZ(file: input, uncalibrated: 5, real: 10, overwrite: true)

        #expect(output == input)
        #expect(FileManager.default.fileExists(atPath: input.path))
    }

    @Test("scaled output is readable as a scene")
    func outputReadable() throws {
        let testRoot = try TestFilesystem.makeTempDirectory(prefix: "scale-readable")
        defer { TestFilesystem.removeIfPresent(testRoot) }

        let input = testRoot.appendingPathComponent("model.usdz")
        try makeSampleUSDZ(at: input)

        let scaler = USDZScaler()
        let output = try scaler.scaleUSDZ(file: input, uncalibrated: 2, real: 3, overwrite: false)

        let scene = try SCNScene(url: output, options: nil)
        #expect(scene.rootNode.childNodes.isEmpty == false)
    }

    private func makeSampleUSDZ(at url: URL) throws {
        let scene = SCNScene()
        let node = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
        scene.rootNode.addChildNode(node)
        scene.write(to: url, options: nil, delegate: nil, progressHandler: nil)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TestError.sampleGenerationFailed
        }
    }
}

private enum TestError: Error {
    case sampleGenerationFailed
}
