import AppKit
import SceneKit
import SwiftUI

enum MeasurementPhase: Equatable {
    case idle
    case pickPoint1
    case pickPoint2
    case done
}

enum MeasurementEditingCommand: Equatable {
    case none
    case reset
}

struct MeasurementUpdate: Equatable {
    let pointCount: Int
    let distance: Double?
    let phase: MeasurementPhase

    static let idle = MeasurementUpdate(pointCount: 0, distance: nil, phase: .idle)
}

struct SurfaceMeasurementView: NSViewRepresentable {
    fileprivate static let modelHitCategoryMask = 1 << 0
    fileprivate static let overlayHitCategoryMask = 1 << 1

    let modelURL: URL?
    let isMeasurementModeEnabled: Bool
    let editingCommand: MeasurementEditingCommand
    let editingCommandToken: UUID
    let onMeasurementUpdated: (_ update: MeasurementUpdate) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMeasurementUpdated: onMeasurementUpdated)
    }

    func makeNSView(context: Context) -> PointPickingSCNView {
        let view = PointPickingSCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .windowBackgroundColor
        view.isMeasurementModeEnabled = isMeasurementModeEnabled

        view.onHover = { [weak view] location in
            guard let view else { return }
            context.coordinator.handleHover(at: location, in: view)
        }

        view.onPick = { [weak view] location in
            guard let view else { return }
            context.coordinator.handlePick(at: location, in: view)
        }

        view.onModelTap = { [weak view] _ in
            guard let view else { return }
            context.coordinator.handleModelTap(in: view)
        }

        context.coordinator.configure(sceneIn: view, for: modelURL)
        context.coordinator.setMeasurementMode(isMeasurementModeEnabled, in: view)

        return view
    }

    func updateNSView(_ nsView: PointPickingSCNView, context: Context) {
        context.coordinator.onMeasurementUpdated = onMeasurementUpdated

        if context.coordinator.currentModelURL != modelURL {
            context.coordinator.configure(sceneIn: nsView, for: modelURL)
        }

        if context.coordinator.lastMeasurementMode != isMeasurementModeEnabled {
            context.coordinator.setMeasurementMode(isMeasurementModeEnabled, in: nsView)
        }

        if context.coordinator.lastEditingCommandToken != editingCommandToken {
            context.coordinator.lastEditingCommandToken = editingCommandToken
            context.coordinator.apply(command: editingCommand, in: nsView)
        }
    }

    static func dismantleNSView(_ nsView: PointPickingSCNView, coordinator: Coordinator) {
        nsView.onHover = nil
        nsView.onPick = nil
        nsView.onModelTap = nil
        nsView.scene = nil
    }

    @MainActor
    final class Coordinator {
        private struct MaterialSnapshot {
            let fillMode: SCNFillMode
            let diffuseContents: Any?
            let emissionContents: Any?
            let lightingModel: SCNMaterial.LightingModel
        }

        var currentModelURL: URL?
        var lastMeasurementMode = false
        var lastEditingCommandToken = UUID()
        var onMeasurementUpdated: (_ update: MeasurementUpdate) -> Void

        private var phase: MeasurementPhase = .idle
        private var pickedPoints: [SCNVector3] = []
        private var markerNodes: [SCNNode] = []
        private var segmentNode: SCNNode?
        private var hoverNode: SCNNode?
        private var isWireframeEnabled = false
        private var materialSnapshots: [ObjectIdentifier: MaterialSnapshot] = [:]

        init(onMeasurementUpdated: @escaping (_ update: MeasurementUpdate) -> Void) {
            self.onMeasurementUpdated = onMeasurementUpdated
        }

        func configure(sceneIn view: PointPickingSCNView, for modelURL: URL?) {
            currentModelURL = modelURL
            clearMeasurementNodes()
            pickedPoints.removeAll()

            guard let modelURL, FileManager.default.fileExists(atPath: modelURL.path) else {
                view.scene = SCNScene()
                phase = .idle
                emitUpdate()
                return
            }

            do {
                view.scene = try SCNScene(url: modelURL, options: nil)
                view.scene?.rootNode.enumerateChildNodes { node, _ in
                    if node.geometry != nil {
                        node.categoryBitMask = SurfaceMeasurementView.modelHitCategoryMask
                    }
                }
                isWireframeEnabled = false
                materialSnapshots.removeAll()
                applyModelFillMode(in: view)
            } catch {
                view.scene = SCNScene()
            }

            hideHoverNode()
            phase = lastMeasurementMode ? .pickPoint1 : .idle
            emitUpdate()
        }

        func setMeasurementMode(_ enabled: Bool, in view: PointPickingSCNView) {
            lastMeasurementMode = enabled
            view.isMeasurementModeEnabled = enabled

            if enabled {
                phase = pickedPoints.isEmpty ? .pickPoint1 : (pickedPoints.count == 1 ? .pickPoint2 : .done)
            } else {
                hideHoverNode()
                phase = .idle
            }

            emitUpdate()
            view.needsDisplay = true
        }

        func apply(command: MeasurementEditingCommand, in view: PointPickingSCNView) {
            switch command {
            case .none:
                return
            case .reset:
                pickedPoints.removeAll()
                clearMeasurementNodes()
                hideHoverNode()
                phase = lastMeasurementMode ? .pickPoint1 : .idle
                emitUpdate()
                view.needsDisplay = true
            }
        }

        func handleHover(at location: NSPoint, in view: PointPickingSCNView) {
            guard lastMeasurementMode else { return }

            guard let intersection = view.meshIntersection(at: location) else {
                hideHoverNode()
                view.needsDisplay = true
                return
            }

            showHoverNode(at: intersection.worldCoordinates, in: view)
            view.needsDisplay = true
        }

        func handlePick(at location: NSPoint, in view: PointPickingSCNView) {
            guard lastMeasurementMode else { return }
            guard let intersection = view.meshIntersection(at: location) else { return }

            // Third click starts a new measurement from point 1, like Online3DViewer.
            if pickedPoints.count == 2 {
                pickedPoints.removeAll()
                clearMeasurementNodes()
            }

            pickedPoints.append(intersection.worldCoordinates)

            if pickedPoints.count == 1 {
                phase = .pickPoint2
            } else {
                phase = .done
            }

            rebuildMeasurementNodes(in: view)
            emitUpdate()
            view.needsDisplay = true
        }

        func handleModelTap(in view: PointPickingSCNView) {
            guard !lastMeasurementMode else { return }
            isWireframeEnabled.toggle()
            applyModelFillMode(in: view)
            view.needsDisplay = true
        }

        private func emitUpdate() {
            onMeasurementUpdated(
                MeasurementUpdate(
                    pointCount: pickedPoints.count,
                    distance: currentDistance(),
                    phase: phase
                )
            )
        }

        private func currentDistance() -> Double? {
            guard pickedPoints.count == 2 else { return nil }
            return distanceBetween(pickedPoints[0], pickedPoints[1])
        }

        private func rebuildMeasurementNodes(in view: PointPickingSCNView) {
            clearMeasurementNodes()
            guard let root = view.scene?.rootNode else { return }

            if pickedPoints.indices.contains(0) {
                let first = makeMarkerNode(color: .systemBlue)
                first.position = pickedPoints[0]
                markerNodes.append(first)
                root.addChildNode(first)
            }

            if pickedPoints.indices.contains(1) {
                let second = makeMarkerNode(color: .systemOrange)
                second.position = pickedPoints[1]
                markerNodes.append(second)
                root.addChildNode(second)

                addSegment(from: pickedPoints[0], to: pickedPoints[1], in: root)
            }
        }

        private func clearMeasurementNodes() {
            markerNodes.forEach { $0.removeFromParentNode() }
            markerNodes.removeAll()
            segmentNode?.removeFromParentNode()
            segmentNode = nil
        }

        private func showHoverNode(at point: SCNVector3, in view: PointPickingSCNView) {
            guard let root = view.scene?.rootNode else { return }

            if hoverNode == nil {
                let sphere = SCNSphere(radius: 0.005)
                sphere.firstMaterial?.diffuse.contents = NSColor.systemGreen
                sphere.firstMaterial?.emission.contents = NSColor.systemGreen
                let node = SCNNode(geometry: sphere)
                node.categoryBitMask = SurfaceMeasurementView.overlayHitCategoryMask
                hoverNode = node
                root.addChildNode(node)
            }

            hoverNode?.position = point
            hoverNode?.isHidden = false
        }

        private func hideHoverNode() {
            hoverNode?.isHidden = true
        }

        private func makeMarkerNode(color: NSColor) -> SCNNode {
            let sphere = SCNSphere(radius: 0.008)
            sphere.firstMaterial?.diffuse.contents = color
            sphere.firstMaterial?.emission.contents = color
            let node = SCNNode(geometry: sphere)
            node.categoryBitMask = SurfaceMeasurementView.overlayHitCategoryMask
            return node
        }

        private func addSegment(from start: SCNVector3, to end: SCNVector3, in root: SCNNode) {
            let source = SCNGeometrySource(vertices: [start, end])
            let element = SCNGeometryElement(indices: [Int32(0), Int32(1)], primitiveType: .line)
            let geometry = SCNGeometry(sources: [source], elements: [element])
            geometry.firstMaterial?.diffuse.contents = NSColor.systemYellow
            geometry.firstMaterial?.emission.contents = NSColor.systemYellow

            let node = SCNNode(geometry: geometry)
            node.categoryBitMask = SurfaceMeasurementView.overlayHitCategoryMask
            segmentNode = node
            root.addChildNode(node)
        }

        private func distanceBetween(_ a: SCNVector3, _ b: SCNVector3) -> Double {
            let dx = Double(a.x - b.x)
            let dy = Double(a.y - b.y)
            let dz = Double(a.z - b.z)
            return (dx * dx + dy * dy + dz * dz).squareRoot()
        }

        private func applyModelFillMode(in view: PointPickingSCNView) {
            let fillMode: SCNFillMode = isWireframeEnabled ? .lines : .fill
            let isDarkMode = view.isDarkAppearance
            let darkModeWireframeColor = NSColor(calibratedWhite: 0.95, alpha: 1)
            view.scene?.rootNode.enumerateChildNodes { node, _ in
                guard
                    node.categoryBitMask == SurfaceMeasurementView.modelHitCategoryMask,
                    let geometry = node.geometry
                else { return }

                if geometry.materials.isEmpty {
                    let material = SCNMaterial()
                    if isWireframeEnabled {
                        material.fillMode = .lines
                        if isDarkMode {
                            material.lightingModel = .constant
                            material.diffuse.contents = darkModeWireframeColor
                            material.emission.contents = darkModeWireframeColor
                        }
                    } else {
                        material.fillMode = .fill
                    }
                    geometry.materials = [material]
                    return
                }

                geometry.materials.forEach { material in
                    let key = ObjectIdentifier(material)

                    if isWireframeEnabled {
                        if materialSnapshots[key] == nil {
                            materialSnapshots[key] = MaterialSnapshot(
                                fillMode: material.fillMode,
                                diffuseContents: material.diffuse.contents,
                                emissionContents: material.emission.contents,
                                lightingModel: material.lightingModel
                            )
                        }

                        material.fillMode = .lines
                        if isDarkMode {
                            material.lightingModel = .constant
                            material.diffuse.contents = darkModeWireframeColor
                            material.emission.contents = darkModeWireframeColor
                        }
                    } else if let snapshot = materialSnapshots[key] {
                        material.fillMode = snapshot.fillMode
                        material.diffuse.contents = snapshot.diffuseContents
                        material.emission.contents = snapshot.emissionContents
                        material.lightingModel = snapshot.lightingModel
                    } else {
                        material.fillMode = fillMode
                    }
                }
            }

            if !isWireframeEnabled {
                materialSnapshots.removeAll()
            }
        }
    }
}

final class PointPickingSCNView: SCNView {
    var isMeasurementModeEnabled = false
    var onHover: ((NSPoint) -> Void)?
    var onPick: ((NSPoint) -> Void)?
    var onModelTap: ((NSPoint) -> Void)?

    private var trackingAreaRef: NSTrackingArea?
    private var mouseDownLocation: NSPoint?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard isMeasurementModeEnabled else {
            super.mouseMoved(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        onHover?(location)
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        guard isMeasurementModeEnabled else {
            mouseDownLocation = location
            super.mouseDown(with: event)
            return
        }

        onPick?(location)
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        defer { mouseDownLocation = nil }

        guard !isMeasurementModeEnabled else {
            super.mouseUp(with: event)
            return
        }

        super.mouseUp(with: event)

        guard let mouseDownLocation else { return }
        let movement = hypot(location.x - mouseDownLocation.x, location.y - mouseDownLocation.y)
        guard movement < 3 else { return }
        guard meshIntersection(at: location) != nil else { return }
        onModelTap?(location)
    }

    func meshIntersection(at point: NSPoint) -> SCNHitTestResult? {
        let options: [SCNHitTestOption: Any] = [
            .firstFoundOnly: false,
            .ignoreHiddenNodes: true,
            .backFaceCulling: false,
            .categoryBitMask: SurfaceMeasurementView.modelHitCategoryMask
        ]

        let hits = hitTest(point, options: options).filter { $0.node.geometry != nil }
        guard let cameraPosition = pointOfView?.presentation.worldPosition else {
            return hits.first
        }

        return hits.min(by: {
            squaredDistance(from: cameraPosition, to: $0.worldCoordinates)
                < squaredDistance(from: cameraPosition, to: $1.worldCoordinates)
        })
    }

    private func squaredDistance(from a: SCNVector3, to b: SCNVector3) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        let dz = a.z - b.z
        let dx2 = dx * dx
        let dy2 = dy * dy
        let dz2 = dz * dz
        return dx2 + dy2 + dz2
    }

    var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
