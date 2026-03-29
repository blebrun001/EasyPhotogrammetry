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

        view.onHover = { location in
            context.coordinator.handleHover(at: location, in: view)
        }

        view.onPick = { location in
            context.coordinator.handlePick(at: location, in: view)
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

    @MainActor
    final class Coordinator {
        var currentModelURL: URL?
        var lastMeasurementMode = false
        var lastEditingCommandToken = UUID()
        var onMeasurementUpdated: (_ update: MeasurementUpdate) -> Void

        private var phase: MeasurementPhase = .idle
        private var pickedPoints: [SCNVector3] = []
        private var markerNodes: [SCNNode] = []
        private var segmentNode: SCNNode?
        private var distanceLabelNode: SCNNode?
        private var hoverNode: SCNNode?

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
                addDistanceLabel(distanceBetween(pickedPoints[0], pickedPoints[1]), between: pickedPoints[0], and: pickedPoints[1], in: root)
            }
        }

        private func clearMeasurementNodes() {
            markerNodes.forEach { $0.removeFromParentNode() }
            markerNodes.removeAll()
            segmentNode?.removeFromParentNode()
            segmentNode = nil
            distanceLabelNode?.removeFromParentNode()
            distanceLabelNode = nil
        }

        private func showHoverNode(at point: SCNVector3, in view: PointPickingSCNView) {
            guard let root = view.scene?.rootNode else { return }

            if hoverNode == nil {
                let sphere = SCNSphere(radius: 0.003)
                sphere.firstMaterial?.diffuse.contents = NSColor.systemGreen
                sphere.firstMaterial?.emission.contents = NSColor.systemGreen
                let node = SCNNode(geometry: sphere)
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
            let sphere = SCNSphere(radius: 0.004)
            sphere.firstMaterial?.diffuse.contents = color
            sphere.firstMaterial?.emission.contents = color
            return SCNNode(geometry: sphere)
        }

        private func addSegment(from start: SCNVector3, to end: SCNVector3, in root: SCNNode) {
            let source = SCNGeometrySource(vertices: [start, end])
            let element = SCNGeometryElement(indices: [Int32(0), Int32(1)], primitiveType: .line)
            let geometry = SCNGeometry(sources: [source], elements: [element])
            geometry.firstMaterial?.diffuse.contents = NSColor.systemYellow
            geometry.firstMaterial?.emission.contents = NSColor.systemYellow

            let node = SCNNode(geometry: geometry)
            segmentNode = node
            root.addChildNode(node)
        }

        private func addDistanceLabel(_ distance: Double, between a: SCNVector3, and b: SCNVector3, in root: SCNNode) {
            let text = SCNText(string: String(format: "%.6f", distance), extrusionDepth: 0.0)
            text.font = NSFont.systemFont(ofSize: 8, weight: .medium)
            text.flatness = 0.2
            text.firstMaterial?.diffuse.contents = NSColor.labelColor
            text.firstMaterial?.isDoubleSided = true

            let node = SCNNode(geometry: text)
            node.scale = SCNVector3(0.002, 0.002, 0.002)
            node.constraints = [SCNBillboardConstraint()]

            let midpoint = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
            node.position = SCNVector3(midpoint.x, midpoint.y + 0.005, midpoint.z)

            distanceLabelNode = node
            root.addChildNode(node)
        }

        private func distanceBetween(_ a: SCNVector3, _ b: SCNVector3) -> Double {
            let dx = Double(a.x - b.x)
            let dy = Double(a.y - b.y)
            let dz = Double(a.z - b.z)
            return (dx * dx + dy * dy + dz * dz).squareRoot()
        }
    }
}

final class PointPickingSCNView: SCNView {
    var isMeasurementModeEnabled = false
    var onHover: ((NSPoint) -> Void)?
    var onPick: ((NSPoint) -> Void)?

    private var trackingAreaRef: NSTrackingArea?

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
        guard isMeasurementModeEnabled else {
            super.mouseDown(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        onPick?(location)
    }

    func meshIntersection(at point: NSPoint) -> SCNHitTestResult? {
        let options: [SCNHitTestOption: Any] = [
            .firstFoundOnly: true,
            .ignoreHiddenNodes: true,
            .backFaceCulling: false
        ]

        return hitTest(point, options: options).first(where: { $0.node.geometry != nil })
    }
}
