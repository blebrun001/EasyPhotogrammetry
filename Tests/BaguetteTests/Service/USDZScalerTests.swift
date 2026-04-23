import Foundation
import SceneKit
import simd
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

    @Test("scaled output bakes mesh bounds and resets node scale")
    func bakedGeometryRemovesScaleTransforms() throws {
        let testRoot = try TestFilesystem.makeTempDirectory(prefix: "scale-baked-bounds")
        defer { TestFilesystem.removeIfPresent(testRoot) }

        let input = testRoot.appendingPathComponent("model.usdz")
        try makeSampleUSDZ(at: input)

        let scaler = USDZScaler()
        let output = try scaler.scaleUSDZ(file: input, uncalibrated: 1, real: 2, overwrite: false)

        let scene = try SCNScene(url: output, options: nil)
        let node = try #require(firstGeometryNode(in: scene.rootNode))
        let size = boundingBoxSize(of: node)

        #expect(abs(size.x - 2) < 0.001)
        #expect(abs(size.y - 2) < 0.001)
        #expect(abs(size.z - 2) < 0.001)
        #expect(abs(node.scale.x - 1) < 0.001)
        #expect(abs(node.scale.y - 1) < 0.001)
        #expect(abs(node.scale.z - 1) < 0.001)
    }

    @Test("scaled output bakes inherited parent scale into child geometry")
    func bakedGeometryIncludesParentScale() throws {
        let testRoot = try TestFilesystem.makeTempDirectory(prefix: "scale-parent-bake")
        defer { TestFilesystem.removeIfPresent(testRoot) }

        let input = testRoot.appendingPathComponent("hierarchy.usdz")
        try makeSampleUSDZ(at: input, parentScale: 3)

        let scaler = USDZScaler()
        let output = try scaler.scaleUSDZ(file: input, uncalibrated: 1, real: 2, overwrite: false)

        let scene = try SCNScene(url: output, options: nil)
        let node = try #require(firstGeometryNode(in: scene.rootNode))
        let size = boundingBoxSize(of: node)

        #expect(abs(size.x - 6) < 0.001)
        #expect(abs(size.y - 6) < 0.001)
        #expect(abs(size.z - 6) < 0.001)

        let parent = try #require(node.parent)
        #expect(abs(parent.scale.x - 1) < 0.001)
        #expect(abs(parent.scale.y - 1) < 0.001)
        #expect(abs(parent.scale.z - 1) < 0.001)
        #expect(abs(node.scale.x - 1) < 0.001)
        #expect(abs(node.scale.y - 1) < 0.001)
        #expect(abs(node.scale.z - 1) < 0.001)
    }

    private func makeSampleUSDZ(at url: URL, parentScale: Float = 1) throws {
        let scene = SCNScene()
        let parentNode = SCNNode()
        parentNode.scale = SCNVector3(parentScale, parentScale, parentScale)
        let node = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
        parentNode.addChildNode(node)
        scene.rootNode.addChildNode(parentNode)
        scene.write(to: url, options: nil, delegate: nil, progressHandler: nil)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TestError.sampleGenerationFailed
        }
    }

    private func firstGeometryNode(in root: SCNNode) -> SCNNode? {
        if root.geometry != nil {
            return root
        }

        for child in root.childNodes {
            if let node = firstGeometryNode(in: child) {
                return node
            }
        }

        return nil
    }

    private func boundingBoxSize(of node: SCNNode) -> SIMD3<Float> {
        let bounds = node.boundingBox
        return SIMD3<Float>(
            Float(bounds.max.x - bounds.min.x),
            Float(bounds.max.y - bounds.min.y),
            Float(bounds.max.z - bounds.min.z)
        )
    }
}

private enum TestError: Error {
    case sampleGenerationFailed
}
