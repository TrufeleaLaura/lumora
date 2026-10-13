import CoreImage
import LumoraCore
import LumoraEngine
import SwiftUI

/// Top-level editor tools (bottom bar).
enum EditorTool: String, CaseIterable, Identifiable {
    case looks, enhance, adjust, masks, retouch, styles, overlays, text, face, body, reshape, crop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .looks: return "Looks"
        case .enhance: return "Enhance"
        case .adjust: return "Adjust"
        case .masks: return "Masks"
        case .retouch: return "Retouch"
        case .styles: return "Styles"
        case .overlays: return "Overlays"
        case .text: return "Text"
        case .face: return "Face"
        case .body: return "Body"
        case .reshape: return "Reshape"
        case .crop: return "Crop"
        }
    }

    var symbol: String {
        switch self {
        case .looks: return "camera.filters"
        case .enhance: return "sparkles"
        case .adjust: return "slider.horizontal.3"
        case .masks: return "circle.dashed"
        case .retouch: return "bandage"
        case .styles: return "wand.and.stars"
        case .overlays: return "square.stack"
        case .text: return "textformat"
        case .face: return "face.smiling"
        case .body: return "figure.stand"
        case .reshape: return "hand.draw"
        case .crop: return "crop.rotate"
        }
    }

    /// Tools whose overlays are drawn in source-photo coordinates (preview skips crop/rotation).
    var showsSourceGeometry: Bool { self == .face || self == .body || self == .masks || self == .retouch || self == .styles || self == .reshape }
}

/// Edits copied with "Copy edits", shared between projects while the app runs.
@MainActor
enum EditClipboard {
    static var document: EditDocument?
}

/// State of one open photo in the editor: the edit document, history, canvas and saving.
@MainActor
final class EditorSession: ObservableObject, Identifiable {
    nonisolated let id: UUID
    let source: ImageSource
    /// Screen-sized pre-rendered copy used for live preview and analysis.
    let proxy: CIImage
    let renderer = CanvasRenderer()

    @Published var document: EditDocument {
        didSet { documentDidChange() }
    }
    @Published var compareMode: CompareMode = .none {
        didSet { renderer.compareMode = compareMode }
    }
    @Published var splitPosition: CGFloat = 0.5 {
        didSet { renderer.splitPosition = splitPosition }
    }
    @Published var activeTool: EditorTool = .adjust {
        didSet {
            guard activeTool != oldValue else { return }
            renderer.allowsZoom = activeTool != .crop
            updateRenderer()
            if activeTool == .face {
                prepareFaces()
            }
            if activeTool == .body {
                prepareBodies()
            }
            if activeTool == .masks || activeTool == .retouch {
                prepareFaces()
            }
            if activeTool == .styles {
                let analysis = self.analysis
                Task.detached(priority: .utility) { _ = analysis.subjectMask }
            }
            updateMaskInteraction()
        }
    }
    // Masks tool
    @Published var selectedMaskID: UUID? {
        didSet { maskSelectionChanged() }
    }
    @Published var selectedComponentID: UUID? {
        didSet { maskSelectionChanged() }
    }
    @Published var maskPanel: MaskPanelMode = .mask {
        didSet { maskSelectionChanged() }
    }
    @Published var showsMaskOverlay = true {
        didSet { updateRenderer() }
    }
    @Published var brush = BrushToolSettings()
    /// Brush: true = one finger paints; false = one finger pans (zoomed in).
    @Published var brushPaints = true {
        didSet { updateMaskInteraction() }
    }
    /// Last painted point (normalized), for the brush cursor.
    @Published var brushCursor: CGPoint?
    /// Set while a mask's automatic analysis (sky, subject, people) runs.
    @Published var preparingMask: String?

    // Retouch tool
    @Published var retouchTool: RetouchTool = .heal {
        didSet { updateMaskInteraction() }
    }
    /// Brush radius as a fraction of the photo width.
    @Published var retouchSize: Double = 0.03
    /// Remove: tap objects instead of painting.
    @Published var removeByTapping = false {
        didSet { updateMaskInteraction() }
    }
    /// The stroke being painted (drawn on the canvas until it's applied).
    @Published var pendingRetouch: BrushStroke?
    /// True while a fill is being computed.
    @Published var isRetouching = false
    /// The clone operation whose source can be dragged.
    @Published var selectedRetouchID: UUID?
    /// Clone: the point to copy from (set by a tap before painting).
    @Published var cloneSource: SIMD2<Double>? {
        didSet { updateMaskInteraction() }
    }
    /// Clone: offset from the stroke being painted to its source.
    @Published var cloneStrokeOffset: SIMD2<Double>?
    /// Styles tool: lens blur focus handles are shown.
    @Published var focusEditing = false
    /// Text tool: the layer being edited.
    @Published var selectedTextID: UUID?
    // Adjust tool: histogram, clipping warning and white-balance picker
    @Published var histogram: HistogramData?
    @Published var showsClipping = false {
        didSet { updateRenderer() }
    }
    @Published var pickingWhiteBalance = false {
        didSet { updateMaskInteraction() }
    }
    var histogramTask: Task<Void, Never>?

    // Reshape tool
    @Published var liquifyTool: LiquifyTool = .push
    @Published var liquifySize: Double = 0.08
    @Published var liquifyStrength: Double = 60
    /// Reshape: true = one finger reshapes; false = one finger moves the photo.
    @Published var liquifyPaints = true {
        didSet { updateMaskInteraction() }
    }

    @Published private(set) var history = EditHistory()
    @Published private(set) var isExporting = false
    @Published var toast: String?

    private let store: ProjectStore
    let pipeline = RenderPipeline()
    private let proxyScale: CGFloat
    /// Per-photo analysis shared by preview, zoom refinement and export.
    let analysis: ImageAnalysis
    private var pendingBefore: EditDocument?
    private var autosaveTask: Task<Void, Never>?

    init(projectID: UUID, source: ImageSource, proxy: CIImage, document: EditDocument, store: ProjectStore) {
        self.id = projectID
        self.source = source
        self.proxy = proxy
        self.document = document
        self.store = store
        self.proxyScale = proxy.extent.width / max(source.pixelSize.width, 1)
        let analysis = ImageAnalysis(image: proxy, mattes: source.mattes)
        self.analysis = analysis
        Task.detached(priority: .utility) {
            analysis.prewarm()
        }

        renderer.originalImage = proxy
        renderer.fullResolutionSize = source.pixelSize
        renderer.onHoldChanged = { [weak self] holding in
            guard let self else { return }
            if holding {
                self.compareMode = .holding
            } else if self.compareMode == .holding {
                self.compareMode = .none
            }
        }
        updateRenderer()
    }

    // MARK: - Rendering

    private func documentDidChange() {
        updateRenderer()
        scheduleAutosave()
    }

    func updateRenderer() {
        let document = self.document
        let original = source.original
        let analysis = self.analysis
        let includeCrop = activeTool != .crop
        let includeGeometry = !activeTool.showsSourceGeometry
        let preview = pipeline.apply(document, to: proxy, scale: proxyScale, analysis: analysis, includeCrop: includeCrop, includeGeometry: includeGeometry)
        // Masks tool: tint the selected mask's area.
        let overlayMask = activeTool == .masks && showsMaskOverlay && maskPanel == .mask ? selectedMask : nil
        if let overlayMask {
            renderer.previewImage = pipeline.maskOverlay(overlayMask, on: preview, reference: proxy, analysis: analysis)
        } else if activeTool == .adjust && showsClipping {
            renderer.previewImage = Histogram.clippingOverlay(preview)
        } else {
            renderer.previewImage = preview
        }
        if activeTool == .adjust {
            scheduleHistogram(preview)
        }
        renderer.fullResolutionImage = {
            let pipeline = RenderPipeline()
            let full = pipeline.apply(document, to: original, scale: 1, analysis: analysis, includeCrop: includeCrop, includeGeometry: includeGeometry)
            guard let overlayMask else { return full }
            return pipeline.maskOverlay(overlayMask, on: full, reference: original, analysis: analysis)
        }
    }

    // MARK: - Editing & history

    /// Two-way binding to any part of the document (use with begin/endChange for undo).
    func binding<Value>(_ keyPath: WritableKeyPath<EditDocument, Value>) -> Binding<Value> {
        Binding(
            get: { self.document[keyPath: keyPath] },
            set: { self.document[keyPath: keyPath] = $0 }
        )
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    /// Call when a continuous change (slider drag) starts; the whole drag becomes one undo step.
    func beginChange() {
        if pendingBefore == nil {
            pendingBefore = document
        }
    }

    func endChange(label: String) {
        if let before = pendingBefore {
            history.record(label: label, before: before, after: document)
        }
        pendingBefore = nil
    }

    /// Applies a discrete change as a single undo step.
    func perform(_ label: String, _ change: (inout EditDocument) -> Void) {
        var updated = document
        change(&updated)
        guard updated != document else { return }
        history.record(label: label, before: document, after: updated)
        document = updated
    }

    func reset(_ spec: SliderSpec) {
        perform("Reset \(spec.title)") { $0[keyPath: spec.keyPath] = spec.defaultValue }
    }

    func resetAll() {
        perform("Reset all") { $0 = EditDocument() }
    }

    func undo() {
        if let previous = history.undo() {
            document = previous
        }
    }

    func redo() {
        if let next = history.redo() {
            document = next
        }
    }

    /// Jumps to the state after `appliedCount` history steps (0 = original).
    func jumpToHistory(appliedCount: Int) {
        if let target = history.jump(toAppliedCount: appliedCount) {
            document = target
        }
    }

    // MARK: - Face

    /// Faces found in the photo (nil while detection hasn't finished).
    @Published private(set) var faces: [FaceLandmarks]?
    /// nil = edit all faces together.
    @Published private(set) var selectedFaceIndex: Int?

    func prepareFaces() {
        guard faces == nil else { return }
        let analysis = self.analysis
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                analysis.faces.map(\.landmarks)
            }.value
            faces = found
            updateRenderer()
        }
    }

    /// The face settings the Face panel edits right now.
    var faceTarget: WritableKeyPath<EditDocument, FaceRetouchSettings> {
        guard let index = selectedFaceIndex, let faces, index < faces.count,
              let editIndex = document.beauty.faces.firstIndex(where: { $0.anchor.matches(faces[index].anchor) }) else {
            return \EditDocument.beauty.allFaces
        }
        return \EditDocument.beauty.faces[editIndex].settings
    }

    /// Selects one face for individual edits (starting from the all-faces settings), or nil for all.
    func selectFace(_ index: Int?) {
        selectedFaceIndex = index
        guard let index, let faces, index < faces.count else { return }
        let anchor = faces[index].anchor
        if !document.beauty.faces.contains(where: { $0.anchor.matches(anchor) }) {
            document.beauty.faces.append(FaceEdit(anchor: anchor, settings: document.beauty.allFaces))
        }
    }

    func autoBeauty() {
        let target = faceTarget
        perform("Auto beauty") { document in
            var settings = FaceCatalog.autoBeauty
            let current = document[keyPath: target]
            // Keep any shape changes the user already made.
            settings.eyeSize = current.eyeSize
            settings.eyeDistance = current.eyeDistance
            settings.faceSlim = current.faceSlim
            settings.cheekbones = current.cheekbones
            settings.jaw = current.jaw
            settings.chin = current.chin
            settings.forehead = current.forehead
            settings.faceLength = current.faceLength
            settings.noseWidth = current.noseWidth
            settings.noseLength = current.noseLength
            settings.noseTip = current.noseTip
            settings.lipsFullness = current.lipsFullness
            settings.lipsWidth = current.lipsWidth
            settings.smile = current.smile
            document[keyPath: target] = settings
        }
    }

    func setMakeupColor(_ color: MakeupColor, name: String, at keyPath: WritableKeyPath<MakeupSettings, MakeupColor>) {
        let target = faceTarget.appending(path: \FaceRetouchSettings.makeup).appending(path: keyPath)
        perform("Color \(name)") { $0[keyPath: target] = color }
    }

    func setLipFinish(_ finish: LipFinish) {
        let target = faceTarget.appending(path: \FaceRetouchSettings.makeup.lipFinish)
        perform("Lip finish \(finish.title)") { $0[keyPath: target] = finish }
    }

    func resetFace() {
        let target = faceTarget
        perform("Reset face") { $0[keyPath: target] = FaceRetouchSettings() }
    }

    // MARK: - Body

    /// People found in the photo (nil while detection hasn't finished).
    @Published private(set) var bodies: [BodyShape]?
    /// nil = edit all people together.
    @Published private(set) var selectedBodyIndex: Int?

    func prepareBodies() {
        guard bodies == nil else { return }
        let analysis = self.analysis
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                analysis.bodies
            }.value
            bodies = found
            updateRenderer()
        }
    }

    var bodyTarget: WritableKeyPath<EditDocument, BodySettings> {
        guard let index = selectedBodyIndex, let bodies, index < bodies.count, let anchor = bodies[index].pose.anchor,
              let editIndex = document.body.bodies.firstIndex(where: { $0.anchor.matches(anchor) }) else {
            return \EditDocument.body.allBodies
        }
        return \EditDocument.body.bodies[editIndex].settings
    }

    func selectBody(_ index: Int?) {
        selectedBodyIndex = index
        guard let index, let bodies, index < bodies.count, let anchor = bodies[index].pose.anchor else { return }
        if !document.body.bodies.contains(where: { $0.anchor.matches(anchor) }) {
            document.body.bodies.append(BodyEdit(anchor: anchor, settings: document.body.allBodies))
        }
    }

    func resetBody() {
        let target = bodyTarget
        perform("Reset body") { $0[keyPath: target] = BodySettings() }
    }

    // MARK: - Crop & rotate

    /// Size of the rotated (uncropped) preview, which crop rectangles are relative to.
    private var uncroppedSize: CGSize {
        let size = proxy.extent.size
        let rotated = GeometryMath.rotatedSize(width: Double(size.width), height: Double(size.height), quarterTurns: document.geometry.quarterTurns)
        return CGSize(width: rotated.0, height: rotated.1)
    }

    /// Pixel size of the exported image (after rotation and crop).
    var outputPixelSize: CGSize {
        let size = source.pixelSize
        let geometry = document.geometry
        let rotated = GeometryMath.rotatedSize(width: Double(size.width), height: Double(size.height), quarterTurns: geometry.quarterTurns)
        return CGSize(width: rotated.0 * geometry.crop.width, height: rotated.1 * geometry.crop.height)
    }

    func setAspect(_ preset: AspectRatioPreset) {
        let size = uncroppedSize
        perform("Aspect \(preset.title)") { document in
            document.geometry.aspect = preset
            if let ratio = preset.ratio(originalWidth: Double(size.width), originalHeight: Double(size.height)) {
                document.geometry.crop = GeometryMath.crop(aspect: ratio, imageWidth: Double(size.width), imageHeight: Double(size.height))
            }
        }
    }

    func rotateClockwise() {
        perform("Rotate") { document in
            var geometry = document.geometry
            geometry.quarterTurns = (geometry.quarterTurns + 1) % 4
            let crop = geometry.crop
            geometry.crop = CropRect(x: crop.y, y: 1 - crop.x - crop.width, width: crop.height, height: crop.width).clamped(minimumSize: 0.01)
            geometry.aspect = geometry.aspect.rotated
            document.geometry = geometry
        }
    }

    /// Flips as seen on screen. Flips are applied before rotation, so with an odd number of
    /// quarter turns a horizontal flip on screen is a vertical flip of the source.
    func flip(horizontal: Bool) {
        perform(horizontal ? "Flip horizontal" : "Flip vertical") { document in
            var geometry = document.geometry
            let oddTurns = geometry.quarterTurns % 2 == 1
            if horizontal != oddTurns {
                geometry.flipHorizontal.toggle()
            } else {
                geometry.flipVertical.toggle()
            }
            if horizontal {
                geometry.crop.x = 1 - geometry.crop.x - geometry.crop.width
                geometry.horizontal = -geometry.horizontal
            } else {
                geometry.crop.y = 1 - geometry.crop.y - geometry.crop.height
                geometry.vertical = -geometry.vertical
            }
            geometry.straighten = -geometry.straighten
            document.geometry = geometry
        }
    }

    func resetGeometry() {
        perform("Reset crop") { $0.geometry = GeometrySettings() }
    }

    func autoStraighten() {
        var level = document.geometry
        level.straighten = 0
        level.vertical = 0
        level.horizontal = 0
        level.crop = .full
        let image = ImageSource.scaled(pipeline.applyGeometry(level, to: proxy, includeCrop: false), maxDimension: 1024)
        Task {
            let tilt = await Task.detached(priority: .userInitiated) {
                HorizonDetector.tilt(of: image)
            }.value
            if let tilt, abs(tilt) > 0.05, abs(tilt) <= 45 {
                perform("Auto straighten") { $0.geometry.straighten = (tilt * 10).rounded() / 10 }
            } else {
                showToast("No tilted horizon found")
            }
        }
    }

    func copyEdits() {
        EditClipboard.document = document
        showToast("Edits copied")
    }

    var canPasteEdits: Bool { EditClipboard.document != nil }

    func pasteEdits() {
        guard let copied = EditClipboard.document else { return }
        perform("Paste edits") { $0 = copied.adjustmentsOnly(keeping: $0.geometry) }
    }

    // MARK: - Looks & presets

    /// Small renders of looks/presets on this photo.
    lazy var lookThumbnails = LookThumbnails(proxy: proxy, fullSize: source.pixelSize)

    func selectLook(_ look: Look?) {
        guard let look else {
            perform("No look") { $0.look = LookSettings() }
            return
        }
        perform("Look \(look.name)") { document in
            let amount = document.look.lookID == look.id ? document.look.amount : 100
            document.look = LookSettings(look: look, amount: amount)
        }
    }

    func applyPreset(_ preset: UserPreset) {
        perform("Preset \(preset.name)") { $0 = preset.document.adjustmentsOnly(keeping: $0.geometry) }
    }

    func saveCurrentAsPreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try PresetStore.shared.save(name: trimmed.isEmpty ? "My preset" : trimmed, document: document)
            showToast("Preset saved")
        } catch {
            showToast("Couldn't save preset: \(error.localizedDescription)")
        }
    }

    // MARK: - Persistence

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.saveDocument()
        }
    }

    private func saveDocument() {
        do {
            try store.save(document: document, for: id)
        } catch {
            showToast("Couldn't save: \(error.localizedDescription)")
        }
    }

    /// Saves the document and a fresh thumbnail. Call when leaving the editor.
    func finish() {
        autosaveTask?.cancel()
        saveDocument()
        let rendered = pipeline.apply(document, to: proxy, scale: proxyScale, analysis: analysis)
        if let thumbnail = Exporter.thumbnailJPEG(rendered) {
            try? store.saveThumbnail(thumbnail, for: id)
        }
    }

    // MARK: - Export

    /// Renders at full resolution and encodes with `options`.
    func exportData(options: ExportOptions) async throws -> Data {
        let document = self.document
        let original = source.original
        let properties = source.properties
        let analysis = self.analysis
        return try await Task.detached(priority: .userInitiated) { () throws -> Data in
            let rendered = RenderPipeline().apply(document, to: original, scale: 1, analysis: analysis)
            do {
                return try Exporter.export(rendered, options: options, sourceProperties: properties)
            } catch {
                // Some devices/simulators can't encode HEIC; fall back to JPEG.
                guard options.format == .heic else { throw error }
                var fallback = options
                fallback.format = .jpeg
                return try Exporter.export(rendered, options: fallback, sourceProperties: properties)
            }
        }.value
    }

    func saveToPhotos(options: ExportOptions) {
        guard !isExporting else { return }
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let data = try await exportData(options: options)
                try await PhotoLibrary.save(imageData: data)
                showToast("Saved to Photos")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    /// Exports to a temporary file for the share sheet.
    func exportFile(options: ExportOptions) async -> URL? {
        guard !isExporting else { return nil }
        isExporting = true
        defer { isExporting = false }
        do {
            let data = try await exportData(options: options)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let ext = Exporter.fileExtension(forEncoded: data) ?? options.format.fileExtension
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Lumora-\(formatter.string(from: Date())).\(ext)")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            showToast(error.localizedDescription)
            return nil
        }
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toast == message {
                toast = nil
            }
        }
    }
}
