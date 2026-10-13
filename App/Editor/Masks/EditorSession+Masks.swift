import CoreImage
import LumoraCore
import LumoraEngine
import SwiftUI

/// What the Masks panel shows for the selected mask.
enum MaskPanelMode: String, CaseIterable, Identifiable {
    case mask, adjust

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mask: return "Mask"
        case .adjust: return "Adjust"
        }
    }
}

/// Brush options for new strokes.
struct BrushToolSettings: Equatable {
    /// Radius as a fraction of the photo width.
    var size: Double = 0.05
    var feather: Double = 50
    var flow: Double = 100
    var erase = false
}

extension EditorSession {
    // MARK: - Selection

    var selectedMaskIndex: Int? {
        guard let selectedMaskID else { return nil }
        return document.masks.firstIndex { $0.id == selectedMaskID }
    }

    var selectedMask: Mask? {
        selectedMaskIndex.map { document.masks[$0] }
    }

    var selectedComponentIndex: Int? {
        guard let maskIndex = selectedMaskIndex, let selectedComponentID else { return nil }
        return document.masks[maskIndex].components.firstIndex { $0.id == selectedComponentID }
    }

    var selectedComponent: MaskComponent? {
        guard let maskIndex = selectedMaskIndex, let componentIndex = selectedComponentIndex else { return nil }
        return document.masks[maskIndex].components[componentIndex]
    }

    /// Key path of the selected component (for sliders).
    var componentPath: WritableKeyPath<EditDocument, MaskComponent>? {
        guard let maskIndex = selectedMaskIndex, let componentIndex = selectedComponentIndex else { return nil }
        return \EditDocument.masks[maskIndex].components[componentIndex]
    }

    func selectMask(_ id: UUID?) {
        selectedMaskID = id
        selectedComponentID = selectedMask?.components.last?.id
    }

    func maskSelectionChanged() {
        updateMaskInteraction()
        updateRenderer()
    }

    /// Hooks canvas paint/tap gestures up to the selected component.
    func updateMaskInteraction() {
        guard activeTool == .masks, maskPanel == .mask, let component = selectedComponent else {
            renderer.onPaint = nil
            renderer.onTap = nil
            return
        }
        switch component.kind {
        case .brush:
            renderer.onTap = nil
            if brushPaints {
                renderer.onPaint = { [weak self] phase, point in self?.paint(phase, at: point) }
            } else {
                renderer.onPaint = nil
            }
        case .color, .object, .point, .people:
            renderer.onPaint = nil
            renderer.onTap = { [weak self] point in self?.tapped(at: point) }
        default:
            renderer.onPaint = nil
            renderer.onTap = nil
        }
    }

    // MARK: - Creating

    func addMask(_ kind: MaskKind) {
        let component = newComponent(kind)
        let mask = Mask(name: MaskCatalog.suggestedName(for: kind, existing: document.masks), components: [component])
        prepareAnalysis(for: kind) { [weak self] in
            guard let self else { return }
            self.perform("New \(kind.title.lowercased()) mask") { $0.masks.append(mask) }
            self.maskPanel = .mask
            self.showsMaskOverlay = true
            self.selectedMaskID = mask.id
            self.selectedComponentID = component.id
        }
    }

    func addComponent(_ kind: MaskKind, mode: MaskMode) {
        guard selectedMaskIndex != nil else { return }
        let component = newComponent(kind, mode: mode)
        prepareAnalysis(for: kind) { [weak self] in
            guard let self, let maskIndex = self.selectedMaskIndex else { return }
            self.perform("\(mode.title) \(kind.title.lowercased())") { $0.masks[maskIndex].components.append(component) }
            self.selectedComponentID = component.id
        }
    }

    private func newComponent(_ kind: MaskKind, mode: MaskMode = .add) -> MaskComponent {
        var component = MaskCatalog.component(kind, mode: mode)
        if kind == .point {
            component.colors = [sampleColor(at: component.start)]
        }
        if kind == .brush {
            component.autoEdge = false
        }
        return component
    }

    /// Runs slow photo analysis off the main thread before showing a mask that needs it.
    private func prepareAnalysis(for kind: MaskKind, then action: @escaping () -> Void) {
        let analysis = self.analysis
        let work: @Sendable () -> String?
        switch kind {
        case .sky:
            work = { analysis.skyCoefficients == nil ? "No sky found in this photo" : nil }
        case .subject, .background:
            work = { analysis.subjectMask == nil ? "No subject found" : nil }
        case .object:
            work = { analysis.subject == nil ? "Object selection isn't available for this photo" : nil }
        case .people:
            work = {
                let faces = analysis.faces
                return analysis.personMask == nil && faces.isEmpty ? "No people found" : nil
            }
        default:
            action()
            return
        }
        preparingMask = "Finding \(kind.title.lowercased())…"
        Task {
            let message = await Task.detached(priority: .userInitiated) { work() }.value
            preparingMask = nil
            if let message {
                showToast(message)
            }
            action()
        }
    }

    // MARK: - Mask actions

    func deleteSelectedMask() {
        guard let index = selectedMaskIndex else { return }
        let name = document.masks[index].name
        perform("Delete \(name)") { $0.masks.remove(at: index) }
        selectMask(document.masks.last?.id)
    }

    func duplicateSelectedMask() {
        guard let index = selectedMaskIndex else { return }
        var copy = document.masks[index]
        copy.id = UUID()
        copy.name += " copy"
        copy.components = copy.components.map { component in
            var component = component
            component.id = UUID()
            return component
        }
        perform("Duplicate mask") { $0.masks.insert(copy, at: index + 1) }
        selectMask(copy.id)
    }

    func toggleSelectedMaskVisibility() {
        guard let index = selectedMaskIndex else { return }
        let visible = document.masks[index].isVisible
        perform(visible ? "Hide mask" : "Show mask") { $0.masks[index].isVisible.toggle() }
    }

    func renameSelectedMask(_ name: String) {
        guard let index = selectedMaskIndex else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        perform("Rename mask") { $0.masks[index].name = trimmed }
    }

    func resetSelectedMaskAdjustments() {
        guard let index = selectedMaskIndex else { return }
        perform("Reset mask adjustments") { document in
            document.masks[index].adjustments = LocalAdjustments()
            document.masks[index].amount = 100
        }
    }

    // MARK: - Component actions

    /// Applies a discrete change to the selected component as one undo step.
    func updateComponent(_ label: String, _ change: (inout MaskComponent) -> Void) {
        guard let path = componentPath else { return }
        perform(label) { change(&$0[keyPath: path]) }
    }

    /// Live change while dragging a handle (wrap in beginChange/endChange).
    func dragComponent(_ change: (inout MaskComponent) -> Void) {
        guard let path = componentPath else { return }
        change(&document[keyPath: path])
    }

    func deleteSelectedComponent() {
        guard let maskIndex = selectedMaskIndex, let componentIndex = selectedComponentIndex else { return }
        if document.masks[maskIndex].components.count <= 1 {
            deleteSelectedMask()
            return
        }
        perform("Delete mask part") { $0.masks[maskIndex].components.remove(at: componentIndex) }
        selectedComponentID = document.masks[maskIndex].components.last?.id
    }

    func clearSelectedComponent() {
        updateComponent("Clear") { component in
            component.strokes = []
            component.colors = []
            component.points = []
        }
        brushCursor = nil
    }

    func togglePart(_ part: PersonPart) {
        updateComponent(part.title) { component in
            if let index = component.parts.firstIndex(of: part) {
                if component.parts.count > 1 {
                    component.parts.remove(at: index)
                }
            } else {
                component.parts.append(part)
            }
        }
    }

    // MARK: - Canvas input

    private var photoAspect: Double {
        let extent = proxy.extent
        return Double(extent.height / max(extent.width, 1))
    }

    func paint(_ phase: PaintPhase, at point: CGPoint) {
        guard let path = componentPath else { return }
        let p = SIMD2(Double(point.x), Double(point.y))
        brushCursor = point
        switch phase {
        case .began:
            beginChange()
            let stroke = BrushStroke(points: [p], radius: brush.size, feather: brush.feather, flow: brush.flow, erase: brush.erase)
            document[keyPath: path].strokes.append(stroke)
        case .moved, .ended:
            guard let last = document[keyPath: path].strokes.last?.points.last else { return }
            let dx = p.x - last.x
            let dy = (p.y - last.y) * photoAspect
            let distance = (dx * dx + dy * dy).squareRoot()
            let strokeIndex = document[keyPath: path].strokes.count - 1
            if distance >= brush.size * 0.2 || (phase == .ended && distance > 0) {
                document[keyPath: path].strokes[strokeIndex].points.append(p)
            }
            if phase == .ended {
                endChange(label: brush.erase ? "Erase" : "Brush")
            }
        }
    }

    func tapped(at point: CGPoint) {
        guard let component = selectedComponent else { return }
        let p = SIMD2(Double(point.x), Double(point.y))
        guard (0...1).contains(p.x), (0...1).contains(p.y) else { return }
        switch component.kind {
        case .color:
            guard component.colors.count < 5 else {
                showToast("Up to 5 colors — clear to start over")
                return
            }
            let color = sampleColor(at: p)
            updateComponent("Pick color") { component in
                component.colors.append(color)
                component.points.append(p)
            }
        case .point:
            let color = sampleColor(at: p)
            updateComponent("Move control point") { component in
                component.start = p
                component.colors = [color]
            }
        case .object:
            if analysis.subject?.instances(at: [p]).isEmpty ?? true {
                showToast("No object found there")
                return
            }
            updateComponent("Select object") { $0.points.append(p) }
        case .people:
            updateComponent("Choose person") { $0.person = p }
        default:
            break
        }
    }

    /// Average color (OKLab) of the unedited photo around a normalized point.
    func sampleColor(at point: SIMD2<Double>) -> SIMD3<Double> {
        let extent = proxy.extent
        let size = max(3, extent.width * 0.006)
        let rect = CGRect(
            x: extent.minX + CGFloat(point.x) * extent.width - size / 2,
            y: extent.minY + CGFloat(point.y) * extent.height - size / 2,
            width: size,
            height: size
        ).intersection(extent)
        let color = ImageStats.averageColor(of: proxy.cropped(to: rect))
        let lab = ColorMath.linearSRGBToOklab(Double(color.x), Double(color.y), Double(color.z))
        return SIMD3(lab.0, lab.1, lab.2)
    }

    /// Re-samples a control point's color after it was dragged.
    func resampleControlPoint() {
        guard let component = selectedComponent, component.kind == .point else { return }
        let color = sampleColor(at: component.start)
        dragComponent { $0.colors = [color] }
    }
}
