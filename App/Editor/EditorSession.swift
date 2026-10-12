import CoreImage
import LumoraCore
import LumoraEngine
import SwiftUI

/// State of one open photo in the editor: the edit document, history and rendering.
@MainActor
final class EditorSession: ObservableObject, Identifiable {
    let id = UUID()
    let source: ImageSource
    /// Screen-sized pre-rendered copy used for live preview.
    let proxy: CIImage

    @Published var document = EditDocument()
    @Published var isShowingOriginal = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var isExporting = false
    @Published var toast: String?

    private var history = UndoStack<EditDocument>()
    private var pendingSnapshot: EditDocument?
    private let pipeline = RenderPipeline()

    init(source: ImageSource) {
        self.source = source
        self.proxy = source.makeProxy(maxDimension: 2048)
    }

    /// The image the canvas should show right now.
    var displayImage: CIImage {
        isShowingOriginal ? proxy : pipeline.apply(document, to: proxy)
    }

    // MARK: - Editing & history

    /// Call when a continuous change (slider drag) starts; the whole drag becomes one undo step.
    func beginChange() {
        if pendingSnapshot == nil {
            pendingSnapshot = document
        }
    }

    func endChange() {
        if let snapshot = pendingSnapshot, snapshot != document {
            history.record(snapshot)
        }
        pendingSnapshot = nil
        refreshHistoryState()
    }

    /// Applies a discrete change as a single undo step.
    func perform(_ change: (inout EditDocument) -> Void) {
        var updated = document
        change(&updated)
        guard updated != document else { return }
        history.record(document)
        document = updated
        refreshHistoryState()
    }

    func reset(_ spec: SliderSpec) {
        perform { $0[keyPath: spec.keyPath] = spec.defaultValue }
    }

    func resetAll() {
        perform { $0 = EditDocument() }
    }

    func undo() {
        if let previous = history.undo(current: document) {
            document = previous
        }
        refreshHistoryState()
    }

    func redo() {
        if let next = history.redo(current: document) {
            document = next
        }
        refreshHistoryState()
    }

    private func refreshHistoryState() {
        canUndo = history.canUndo
        canRedo = history.canRedo
    }

    // MARK: - Export

    func saveToPhotos() {
        guard !isExporting else { return }
        isExporting = true
        let document = self.document
        let original = source.original
        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) { () throws -> Data in
                    let rendered = RenderPipeline().apply(document, to: original)
                    do {
                        return try Exporter.encode(rendered, format: .heic, quality: 0.95)
                    } catch {
                        return try Exporter.encode(rendered, format: .jpeg, quality: 0.95)
                    }
                }.value
                try await PhotoLibrary.save(imageData: data)
                showToast("Saved to Photos")
            } catch {
                showToast(error.localizedDescription)
            }
            isExporting = false
        }
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toast == message {
                toast = nil
            }
        }
    }
}
