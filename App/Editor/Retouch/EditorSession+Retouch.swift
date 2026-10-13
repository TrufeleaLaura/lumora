import CoreImage
import LumoraCore
import LumoraEngine
import SwiftUI

extension EditorSession {
    /// Canvas input for the Retouch tool: paint areas, or tap objects to remove.
    func updateRetouchInteraction() {
        renderer.onPaint = nil
        renderer.onTap = nil
        guard activeTool == .retouch, !isRetouching else { return }
        if retouchTool == .remove && removeByTapping {
            renderer.onTap = { [weak self] point in self?.removeObject(at: point) }
        } else {
            renderer.onPaint = { [weak self] phase, point in self?.paintRetouch(phase, at: point) }
        }
    }

    var selectedRetouchIndex: Int? {
        guard let selectedRetouchID else { return nil }
        return document.retouch.operations.firstIndex { $0.id == selectedRetouchID }
    }

    private var aspect: Double {
        let extent = proxy.extent
        return Double(extent.height / max(extent.width, 1))
    }

    func paintRetouch(_ phase: PaintPhase, at point: CGPoint) {
        let p = SIMD2(Double(point.x), Double(point.y))
        switch phase {
        case .began:
            pendingRetouch = BrushStroke(points: [p], radius: retouchSize, feather: retouchTool == .clone ? 40 : 25, flow: 100)
        case .moved, .ended:
            guard var stroke = pendingRetouch, let last = stroke.points.last else { return }
            let dx = p.x - last.x
            let dy = (p.y - last.y) * aspect
            if (dx * dx + dy * dy).squareRoot() >= stroke.radius * 0.2 {
                stroke.points.append(p)
                pendingRetouch = stroke
            }
            if phase == .ended {
                var operation = RetouchOperation(tool: retouchTool, strokes: [stroke])
                if retouchTool == .clone {
                    operation.sourceOffset = automaticCloneOffset(for: operation)
                }
                commitRetouch(operation)
            }
        }
    }

    /// Clone source: next to the painted area, on whichever side stays inside the photo.
    private func automaticCloneOffset(for operation: RetouchOperation) -> SIMD2<Double> {
        guard let bounds = operation.bounds(aspect: aspect) else { return SIMD2(0.1, 0) }
        let shiftX = bounds.width * 1.25
        if bounds.x + bounds.width + shiftX <= 1 { return SIMD2(shiftX, 0) }
        if bounds.x - shiftX >= 0 { return SIMD2(-shiftX, 0) }
        let shiftY = bounds.height * 1.25
        return bounds.y - shiftY >= 0 ? SIMD2(0, -shiftY) : SIMD2(0, shiftY)
    }

    func removeObject(at point: CGPoint) {
        let p = SIMD2(Double(point.x), Double(point.y))
        guard analysis.objectMask(at: [p]) != nil else {
            showToast("No object found there — paint over it instead")
            return
        }
        var operation = RetouchOperation(tool: .remove)
        operation.objectPoints = [p]
        commitRetouch(operation)
    }

    /// Computes the fill in the background, then adds the operation (so the canvas never stalls).
    func commitRetouch(_ operation: RetouchOperation) {
        var settings = document.retouch
        settings.operations.append(operation)
        let input = proxy
        let analysis = self.analysis
        isRetouching = true
        updateRetouchInteraction()
        Task {
            await Task.detached(priority: .userInitiated) {
                RenderPipeline().prepareRetouch(settings, input: input, analysis: analysis)
            }.value
            perform(operation.tool.title) { $0.retouch.operations.append(operation) }
            pendingRetouch = nil
            isRetouching = false
            selectedRetouchID = operation.tool == .clone ? operation.id : nil
            updateRetouchInteraction()
        }
    }

    /// Moves a clone operation's source (recomputing its patch first).
    func moveCloneSource(_ id: UUID, offset: SIMD2<Double>) {
        guard let index = document.retouch.operations.firstIndex(where: { $0.id == id }) else { return }
        var settings = document.retouch
        settings.operations[index].sourceOffset = offset
        let input = proxy
        let analysis = self.analysis
        isRetouching = true
        updateRetouchInteraction()
        Task {
            await Task.detached(priority: .userInitiated) {
                RenderPipeline().prepareRetouch(settings, input: input, analysis: analysis)
            }.value
            perform("Move clone source") { $0.retouch.operations[index].sourceOffset = offset }
            isRetouching = false
            updateRetouchInteraction()
        }
    }

    func clearRetouching() {
        perform("Clear retouching") { $0.retouch.operations = [] }
        selectedRetouchID = nil
    }

    func undoLastRetouch() {
        guard !document.retouch.operations.isEmpty else { return }
        perform("Remove last fix") { $0.retouch.operations.removeLast() }
        selectedRetouchID = nil
    }
}
