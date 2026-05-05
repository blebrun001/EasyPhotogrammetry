import Foundation
import ModelIO
import SceneKit
import simd

/// Domain errors emitted by the USDZ scaling pipeline.
enum ScalingError: LocalizedError, Equatable {
    case invalidInput(String)
    case fileNotFound(URL)
    case unsupportedFileExtension(String)
    case loadFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        case .fileNotFound(let url):
            return "File not found: \(url.path)."
        case .unsupportedFileExtension(let ext):
            return "Only .usdz files are supported (got .\(ext))."
        case .loadFailed(let message):
            return "Unable to load USDZ scene: \(message)"
        case .writeFailed(let message):
            return "Unable to write scaled USDZ: \(message)"
        }
    }
}

/// Contract for components capable of rescaling USDZ assets.
protocol USDZScaling: Sendable {
    /// Scales a USDZ model by matching an uncalibrated measured distance to its real-world equivalent.
    /// - Parameters:
    ///   - file: Source USDZ file to transform.
    ///   - uncalibrated: Distance measured on the model before scaling.
    ///   - real: Target real-world distance for that same segment.
    ///   - overwrite: Whether to overwrite the source file.
    /// - Returns: URL of the scaled USDZ file.
    /// - Throws: `ScalingError` values when validation, load, or write fails.
    func scaleUSDZ(file: URL, uncalibrated: Double, real: Double, overwrite: Bool) throws -> URL
}

/// Default scaling implementation with a Model I/O primary path and a SceneKit fallback.
final class USDZScaler: USDZScaling, @unchecked Sendable {
    private let fileManager: FileManager

    /// - Parameter fileManager: Injectable file manager used for persistence and tests.
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Validates inputs, computes a uniform scale factor, and persists the scaled USDZ.
    /// - Parameters:
    ///   - file: Source USDZ file.
    ///   - uncalibrated: Measured distance in model units.
    ///   - real: Target real-world distance.
    ///   - overwrite: Whether to overwrite the source file path.
    /// - Returns: Final destination URL of the scaled USDZ.
    /// - Throws: `ScalingError` when validation, loading, or writing fails.
    func scaleUSDZ(file: URL, uncalibrated: Double, real: Double, overwrite: Bool) throws -> URL {
        guard uncalibrated > 0, real > 0 else {
            throw ScalingError.invalidInput("Scaling values must be positive numbers.")
        }

        guard fileManager.fileExists(atPath: file.path) else {
            throw ScalingError.fileNotFound(file)
        }

        let fileExtension = file.pathExtension.lowercased()
        guard fileExtension == "usdz" else {
            throw ScalingError.unsupportedFileExtension(fileExtension)
        }

        let factor = Float(real / uncalibrated)
        let destinationURL: URL
        if overwrite {
            destinationURL = file
        } else {
            destinationURL = file
                .deletingLastPathComponent()
                .appendingPathComponent("scaled_\(file.lastPathComponent)")
        }

        do {
            try scaleUsingModelIO(sourceURL: file, destinationURL: destinationURL, factor: factor)
            return destinationURL
        } catch {
            let modelIOErrorDescription = error.localizedDescription

            do {
                try scaleUsingSceneKit(sourceURL: file, destinationURL: destinationURL, factor: CGFloat(factor))
                return destinationURL
            } catch {
                throw ScalingError.writeFailed(
                    "Model I/O export failed (\(modelIOErrorDescription)). SceneKit fallback failed: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Primary scaling path using Model I/O transforms.
    /// - Parameters:
    ///   - sourceURL: Source USDZ URL.
    ///   - destinationURL: Final destination URL.
    ///   - factor: Uniform scale factor.
    /// - Throws: `ScalingError` when loading or export fails.
    private func scaleUsingModelIO(sourceURL: URL, destinationURL: URL, factor: Float) throws {
        let asset = MDLAsset(url: sourceURL)
        guard asset.count > 0 else {
            throw ScalingError.loadFailed("The asset does not contain any mesh/object.")
        }

        try bakeScale(factor, into: asset)

        let temporaryURL = makeTemporaryOutputURL(near: destinationURL)
        do {
            try asset.export(to: temporaryURL)
        } catch {
            throw ScalingError.writeFailed("Model I/O export failed: \(error.localizedDescription)")
        }

        try finalizeOutput(from: temporaryURL, to: destinationURL)
    }

    /// Fallback scaling path using SceneKit when Model I/O export fails.
    /// - Parameters:
    ///   - sourceURL: Source USDZ URL.
    ///   - destinationURL: Final destination URL.
    ///   - factor: Uniform scale factor.
    /// - Throws: `ScalingError` when scene loading or write fails.
    private func scaleUsingSceneKit(sourceURL: URL, destinationURL: URL, factor: CGFloat) throws {
        let scene: SCNScene
        do {
            scene = try SCNScene(url: sourceURL, options: nil)
        } catch {
            throw ScalingError.loadFailed(error.localizedDescription)
        }

        let bakedScene = makeFlattenedBakedScene(from: scene, factor: factor)

        let temporaryURL = makeTemporaryOutputURL(near: destinationURL)
        bakedScene.write(to: temporaryURL, options: nil, delegate: nil, progressHandler: nil)

        try finalizeOutput(from: temporaryURL, to: destinationURL)
    }

    /// Atomically promotes a temporary file into the final destination.
    /// - Parameters:
    ///   - temporaryURL: Temporary generated USDZ file.
    ///   - destinationURL: Final output URL.
    /// - Throws: `ScalingError.writeFailed` when the destination cannot be updated.
    private func finalizeOutput(from temporaryURL: URL, to destinationURL: URL) throws {
        guard fileManager.fileExists(atPath: temporaryURL.path) else {
            throw ScalingError.writeFailed("The output file was not created.")
        }

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
            throw ScalingError.writeFailed(error.localizedDescription)
        }
    }

    /// Creates a temporary URL near the destination so move operations stay on the same volume.
    /// - Parameter destinationURL: Target output URL.
    /// - Returns: Temporary sibling URL ending in `.usdz`.
    private func makeTemporaryOutputURL(near destinationURL: URL) -> URL {
        destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".tmp_scaled_\(UUID().uuidString).usdz")
    }

    /// Bakes a uniform scale into each mesh of a Model I/O asset and removes scale from transforms.
    /// - Parameters:
    ///   - factor: Multiplicative factor.
    ///   - asset: Asset containing all objects to transform.
    private func bakeScale(_ factor: Float, into asset: MDLAsset) throws {
        for index in 0..<asset.count {
            try bakeScaleRecursively(for: asset.object(at: index), inheritedScale: factor)
        }
    }

    /// Applies a uniform scale transform to each node in the SceneKit hierarchy.
    /// - Parameters:
    ///   - factor: Multiplicative factor.
    ///   - root: Root node to scale recursively.
    private func applyScaleTransforms(_ factor: CGFloat, to root: SCNNode) {
        root.scale = SCNVector3(root.scale.x * factor, root.scale.y * factor, root.scale.z * factor)
    }

    /// Builds a SceneKit scene where scale transforms are baked into geometry.
    /// - Parameters:
    ///   - sourceScene: Source scene to scale.
    ///   - factor: Multiplicative factor.
    /// - Returns: New scene containing flattened geometry with identity scales.
    private func makeFlattenedBakedScene(from sourceScene: SCNScene, factor: CGFloat) -> SCNScene {
        let workingScene = SCNScene()
        let importedRoot = sourceScene.rootNode.clone()
        workingScene.rootNode.addChildNode(importedRoot)
        applyScaleTransforms(factor, to: importedRoot)

        let flattenedRoot = workingScene.rootNode.flattenedClone()
        flattenedRoot.scale = SCNVector3(1, 1, 1)

        let bakedScene = SCNScene()
        bakedScene.rootNode.addChildNode(flattenedRoot)
        return bakedScene
    }

    /// Recursively bakes scale into mesh vertices while preserving translation and rotation.
    /// - Parameters:
    ///   - object: Current object in the recursion.
    ///   - inheritedScale: Uniform scale accumulated from ancestors.
    private func bakeScaleRecursively(for object: MDLObject, inheritedScale: Float) throws {
        let localTransform = ((object.transform as? MDLTransform)?.matrix) ?? matrix_identity_float4x4
        let localScale = uniformScale(in: localTransform)
        let cumulativeScale = inheritedScale * localScale

        if let mesh = object as? MDLMesh {
            try bakeScale(cumulativeScale, into: mesh)
        }

        let transform = MDLTransform()
        transform.matrix = matrixRemovingScale(from: localTransform)
        object.transform = transform

        for child in object.children.objects {
            try bakeScaleRecursively(for: child, inheritedScale: cumulativeScale)
        }
    }

    /// Bakes a uniform scale directly into a Model I/O mesh vertex buffer.
    /// - Parameters:
    ///   - factor: Uniform scale factor to bake.
    ///   - mesh: Target mesh to mutate in place.
    private func bakeScale(_ factor: Float, into mesh: MDLMesh) throws {
        guard factor != 1 else { return }

        guard let positions = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3) else {
            throw ScalingError.loadFailed("The asset contains a mesh without float3 position data.")
        }
        guard positions.stride >= MemoryLayout<Float>.size * 3 else {
            throw ScalingError.loadFailed("Unsupported mesh position layout.")
        }

        let writablePositionCount = writableVertexCount(in: positions, expectedVertexCount: mesh.vertexCount)
        guard writablePositionCount > 0 else {
            throw ScalingError.loadFailed("The mesh position buffer is empty or invalid.")
        }

        for index in 0..<writablePositionCount {
            let base = positions.dataStart.advanced(by: index * positions.stride)
            let x = readFloat(from: base, offset: 0) * factor
            let y = readFloat(from: base, offset: MemoryLayout<Float>.size) * factor
            let z = readFloat(from: base, offset: MemoryLayout<Float>.size * 2) * factor
            writeFloat(x, to: base, offset: 0)
            writeFloat(y, to: base, offset: MemoryLayout<Float>.size)
            writeFloat(z, to: base, offset: MemoryLayout<Float>.size * 2)
        }

        if let normals = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal, as: .float3) {
            guard normals.stride >= MemoryLayout<Float>.size * 3 else {
                throw ScalingError.loadFailed("Unsupported mesh normal layout.")
            }
            let writableNormalCount = writableVertexCount(in: normals, expectedVertexCount: mesh.vertexCount)
            for index in 0..<writableNormalCount {
                let base = normals.dataStart.advanced(by: index * normals.stride)
                let value = SIMD3<Float>(
                    readFloat(from: base, offset: 0),
                    readFloat(from: base, offset: MemoryLayout<Float>.size),
                    readFloat(from: base, offset: MemoryLayout<Float>.size * 2)
                )
                let length = simd_length(value)
                if length > 0 {
                    let normalized = simd_normalize(value)
                    writeFloat(normalized.x, to: base, offset: 0)
                    writeFloat(normalized.y, to: base, offset: MemoryLayout<Float>.size)
                    writeFloat(normalized.z, to: base, offset: MemoryLayout<Float>.size * 2)
                }
            }
        }
    }

    /// Extracts the uniform scale encoded in a transform matrix.
    /// - Parameter matrix: Transform matrix whose basis vectors encode local scale.
    /// - Returns: Average basis magnitude, assuming a uniform scale.
    private func uniformScale(in matrix: simd_float4x4) -> Float {
        let x = simd_length(SIMD3<Float>(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z))
        let y = simd_length(SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z))
        let z = simd_length(SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
        return (x + y + z) / 3
    }

    /// Removes the scale component from a transform matrix while preserving translation and rotation.
    /// - Parameter matrix: Transform matrix to normalize.
    /// - Returns: Equivalent transform with identity scale.
    private func matrixRemovingScale(from matrix: simd_float4x4) -> simd_float4x4 {
        let scale = max(uniformScale(in: matrix), .leastNonzeroMagnitude)
        var normalized = matrix
        normalized.columns.0 /= scale
        normalized.columns.1 /= scale
        normalized.columns.2 /= scale
        normalized.columns.3.w = 1
        return normalized
    }

    /// Reads a float at byte offset from a raw memory address without alignment assumptions.
    private func readFloat(from pointer: UnsafeRawPointer, offset: Int) -> Float {
        var value: Float = 0
        memcpy(&value, pointer.advanced(by: offset), MemoryLayout<Float>.size)
        return value
    }

    /// Writes a float at byte offset to a raw memory address without alignment assumptions.
    private func writeFloat(_ value: Float, to pointer: UnsafeMutableRawPointer, offset: Int) {
        var valueCopy = value
        memcpy(pointer.advanced(by: offset), &valueCopy, MemoryLayout<Float>.size)
    }

    /// Returns a safe writable vertex count from mapped attribute metadata.
    /// - Parameters:
    ///   - attributeData: Mapped attribute data.
    ///   - expectedVertexCount: Expected count from mesh metadata.
    /// - Returns: Count clamped to underlying mapped buffer length.
    private func writableVertexCount(in attributeData: MDLVertexAttributeData, expectedVertexCount: Int) -> Int {
        guard attributeData.stride > 0 else { return 0 }
        guard attributeData.bufferSize > 0 else { return expectedVertexCount }
        return min(expectedVertexCount, attributeData.bufferSize / attributeData.stride)
    }
}
