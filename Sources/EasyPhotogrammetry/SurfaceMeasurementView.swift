import AppKit
import SceneKit
import SwiftUI

/// Measurement interaction lifecycle for the SceneKit picking workflow.
enum MeasurementPhase: Equatable {
    case idle
    case pickPoint1
    case pickPoint2
    case done
}

/// One-shot editing commands sent by SwiftUI to the SceneKit coordinator.
enum MeasurementEditingCommand: Equatable {
    case none
    case reset
}

/// Snapshot sent from SceneKit measurement state back to SwiftUI.
struct MeasurementUpdate: Equatable {
    let pointCount: Int
    let distance: Double?
    let phase: MeasurementPhase

    static let idle = MeasurementUpdate(pointCount: 0, distance: nil, phase: .idle)
}

/// NSViewRepresentable wrapper around SceneKit used to pick points on the generated mesh.
struct SurfaceMeasurementView: NSViewRepresentable {
    fileprivate static let modelHitCategoryMask = 1 << 0
    fileprivate static let overlayHitCategoryMask = 1 << 1

    let modelURL: URL?
    let isMeasurementModeEnabled: Bool
    let editingCommand: MeasurementEditingCommand
    let editingCommandToken: UUID
    let onMeasurementUpdated: (_ update: MeasurementUpdate) -> Void

    /// Creates the coordinator that owns SceneKit state and interaction logic.
    func makeCoordinator() -> Coordinator {
        Coordinator(onMeasurementUpdated: onMeasurementUpdated)
    }

    /// Creates and configures the SceneKit view used for picking and hover interactions.
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

    /// Syncs representable inputs into the coordinator/view without rebuilding the SceneKit view.
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

    /// Detaches callbacks and scene content before view teardown.
    static func dismantleNSView(_ nsView: PointPickingSCNView, coordinator: Coordinator) {
        nsView.onHover = nil
        nsView.onPick = nil
        nsView.onModelTap = nil
        nsView.scene = nil
    }

    @MainActor
    /// Owns all SceneKit state required for measurement, hover feedback, and wireframe toggling.
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

        /// Loads a new model scene and resets measurement overlays when the model URL changes.
        /// - Parameters:
        ///   - view: SceneKit view receiving the scene.
        ///   - modelURL: Optional model URL to load.
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

        /// Enables or disables measurement mode and updates phase accordingly.
        /// - Parameters:
        ///   - enabled: Whether picking mode should be active.
        ///   - view: SceneKit view hosting interactions.
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

        /// Applies one-shot editing commands from SwiftUI.
        /// - Parameters:
        ///   - command: Editing command to apply.
        ///   - view: SceneKit view hosting overlays.
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

        /// Updates hover indicator over the closest mesh intersection under the pointer.
        /// - Parameters:
        ///   - location: Pointer location in view coordinates.
        ///   - view: SceneKit view used for hit testing.
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

        /// Handles click picking and builds measurement overlays from selected points.
        /// - Parameters:
        ///   - location: Click location in view coordinates.
        ///   - view: SceneKit view used for hit testing and overlays.
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

        /// Toggles model wireframe display when measurement mode is off.
        /// - Parameter view: SceneKit view containing the model.
        func handleModelTap(in view: PointPickingSCNView) {
            guard !lastMeasurementMode else { return }
            isWireframeEnabled.toggle()
            applyModelFillMode(in: view)
            view.needsDisplay = true
        }

        /// Emits current measurement state snapshot to SwiftUI.
        private func emitUpdate() {
            onMeasurementUpdated(
                MeasurementUpdate(
                    pointCount: pickedPoints.count,
                    distance: currentDistance(),
                    phase: phase
                )
            )
        }

        /// Returns the current measured distance when two points are available.
        private func currentDistance() -> Double? {
            guard pickedPoints.count == 2 else { return nil }
            return distanceBetween(pickedPoints[0], pickedPoints[1])
        }

        /// Recreates point markers and the connecting segment based on selected points.
        /// - Parameter view: SceneKit view where overlays should be attached.
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

        /// Removes all persistent measurement overlays (markers + segment).
        private func clearMeasurementNodes() {
            markerNodes.forEach { $0.removeFromParentNode() }
            markerNodes.removeAll()
            segmentNode?.removeFromParentNode()
            segmentNode = nil
        }

        /// Shows or creates the hover marker at the given point.
        /// - Parameters:
        ///   - point: World-space intersection point.
        ///   - view: SceneKit view containing the root node.
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

        /// Hides the transient hover marker.
        private func hideHoverNode() {
            hoverNode?.isHidden = true
        }

        /// Creates a measurement marker sphere with category configured for overlay hit filtering.
        /// - Parameter color: Marker color.
        /// - Returns: Configured marker node.
        private func makeMarkerNode(color: NSColor) -> SCNNode {
            let sphere = SCNSphere(radius: 0.008)
            sphere.firstMaterial?.diffuse.contents = color
            sphere.firstMaterial?.emission.contents = color
            let node = SCNNode(geometry: sphere)
            node.categoryBitMask = SurfaceMeasurementView.overlayHitCategoryMask
            return node
        }

        /// Adds a line segment between two picked points.
        /// - Parameters:
        ///   - start: First point.
        ///   - end: Second point.
        ///   - root: Root node that owns the segment overlay.
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

        /// Computes Euclidean distance between two SceneKit vectors.
        private func distanceBetween(_ a: SCNVector3, _ b: SCNVector3) -> Double {
            let dx = Double(a.x - b.x)
            let dy = Double(a.y - b.y)
            let dz = Double(a.z - b.z)
            return (dx * dx + dy * dy + dz * dz).squareRoot()
        }

        /// Applies model fill mode (solid or wireframe) and restores original material snapshots when needed.
        /// - Parameter view: SceneKit view containing model nodes.
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

/// SceneKit view subclass that exposes hover/pick/tap callbacks for the measurement tool.
final class PointPickingSCNView: SCNView {
    var isMeasurementModeEnabled = false
    var onHover: ((NSPoint) -> Void)?
    var onPick: ((NSPoint) -> Void)?
    var onModelTap: ((NSPoint) -> Void)?

    private var trackingAreaRef: NSTrackingArea?
    private var mouseDownLocation: NSPoint?

    /// Keeps a tracking area that follows the visible rect so hover updates remain active.
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

    /// Forwards pointer motion only when measurement mode is enabled.
    override func mouseMoved(with event: NSEvent) {
        guard isMeasurementModeEnabled else {
            super.mouseMoved(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        onHover?(location)
    }

    /// Captures pick interactions in measurement mode and preserves default camera controls otherwise.
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        guard isMeasurementModeEnabled else {
            mouseDownLocation = location
            super.mouseDown(with: event)
            return
        }

        onPick?(location)
    }

    /// Detects click-like taps on the model to toggle wireframe mode when not measuring.
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

    /// Returns the closest mesh hit under a view-space point.
    /// - Parameter point: Hit-test point in view coordinates.
    /// - Returns: Nearest valid mesh intersection if one exists.
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

    /// Squared distance helper used to avoid unnecessary square roots when sorting hits.
    private func squaredDistance(from a: SCNVector3, to b: SCNVector3) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        let dz = a.z - b.z
        let dx2 = dx * dx
        let dy2 = dy * dy
        let dz2 = dz * dz
        return dx2 + dy2 + dz2
    }

    /// Convenience flag for dark appearance specific wireframe styling.
    var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
