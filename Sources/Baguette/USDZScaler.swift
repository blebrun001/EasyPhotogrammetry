import Foundation
import ModelIO
import SceneKit
import simd

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

protocol USDZScaling {
    func scaleUSDZ(file: URL, uncalibrated: Double, real: Double, overwrite: Bool) throws -> URL
}

final class USDZScaler: USDZScaling {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

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

    private func scaleUsingModelIO(sourceURL: URL, destinationURL: URL, factor: Float) throws {
        let asset = MDLAsset(url: sourceURL)
        guard asset.count > 0 else {
            throw ScalingError.loadFailed("The asset does not contain any mesh/object.")
        }

        applyScale(factor, to: asset)

        let temporaryURL = makeTemporaryOutputURL(near: destinationURL)
        do {
            try asset.export(to: temporaryURL)
        } catch {
            throw ScalingError.writeFailed("Model I/O export failed: \(error.localizedDescription)")
        }

        try finalizeOutput(from: temporaryURL, to: destinationURL)
    }

    private func scaleUsingSceneKit(sourceURL: URL, destinationURL: URL, factor: CGFloat) throws {
        let scene: SCNScene
        do {
            scene = try SCNScene(url: sourceURL, options: nil)
        } catch {
            throw ScalingError.loadFailed(error.localizedDescription)
        }

        applyScale(factor, to: scene.rootNode)

        let temporaryURL = makeTemporaryOutputURL(near: destinationURL)
        scene.write(to: temporaryURL, options: nil, delegate: nil, progressHandler: nil)

        try finalizeOutput(from: temporaryURL, to: destinationURL)
    }

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

    private func makeTemporaryOutputURL(near destinationURL: URL) -> URL {
        destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".tmp_scaled_\(UUID().uuidString).usdz")
    }

    private func applyScale(_ factor: CGFloat, to root: SCNNode) {
        root.scale = SCNVector3(root.scale.x * factor, root.scale.y * factor, root.scale.z * factor)

        root.enumerateChildNodes { node, _ in
            node.scale = SCNVector3(node.scale.x * factor, node.scale.y * factor, node.scale.z * factor)
        }
    }

    private func applyScale(_ factor: Float, to asset: MDLAsset) {
        for index in 0..<asset.count {
            applyScaleRecursively(factor, to: asset.object(at: index))
        }
    }

    private func applyScaleRecursively(_ factor: Float, to object: MDLObject) {
        let transform = (object.transform as? MDLTransform) ?? MDLTransform()
        let scaleMatrix = uniformScaleMatrix(factor)
        transform.matrix = simd_mul(transform.matrix, scaleMatrix)
        object.transform = transform

        for child in object.children.objects {
            applyScaleRecursively(factor, to: child)
        }
    }

    private func uniformScaleMatrix(_ factor: Float) -> simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(factor, 0, 0, 0),
            SIMD4<Float>(0, factor, 0, 0),
            SIMD4<Float>(0, 0, factor, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }
}
