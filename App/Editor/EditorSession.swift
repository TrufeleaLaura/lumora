import CoreImage
import LumoraCore
import LumoraEngine
import SwiftUI

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
    @Published private(set) var history = EditHistory()
    @Published private(set) var isExporting = false
    @Published var toast: String?

    private let store: ProjectStore
    private let pipeline = RenderPipeline()
    private let proxyScale: CGFloat
    private var pendingBefore: EditDocument?
    private var autosaveTask: Task<Void, Never>?

    init(projectID: UUID, source: ImageSource, proxy: CIImage, document: EditDocument, store: ProjectStore) {
        self.id = projectID
        self.source = source
        self.proxy = proxy
        self.document = document
        self.store = store
        self.proxyScale = proxy.extent.width / max(source.pixelSize.width, 1)

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

    private func updateRenderer() {
        let document = self.document
        let original = source.original
        renderer.previewImage = pipeline.apply(document, to: proxy, scale: proxyScale)
        renderer.fullResolutionImage = {
            RenderPipeline().apply(document, to: original, scale: 1)
        }
    }

    // MARK: - Editing & history

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

    func copyEdits() {
        EditClipboard.document = document
        showToast("Edits copied")
    }

    var canPasteEdits: Bool { EditClipboard.document != nil }

    func pasteEdits() {
        guard let copied = EditClipboard.document else { return }
        perform("Paste edits") { $0 = copied }
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
        let rendered = pipeline.apply(document, to: proxy, scale: proxyScale)
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
        return try await Task.detached(priority: .userInitiated) { () throws -> Data in
            let rendered = RenderPipeline().apply(document, to: original, scale: 1)
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
