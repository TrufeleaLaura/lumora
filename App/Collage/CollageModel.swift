import CoreImage
import LumoraCore
import LumoraEngine
import SwiftUI
import UIKit

/// State of the collage / story maker: layout settings and one photo per cell.
@MainActor
final class CollageModel: ObservableObject {
    struct Cell {
        var image: CIImage?
        var preview: UIImage?
        var crop = CollageCrop()
    }

    /// A rendered photo crossing threads (Core Image values are immutable).
    private struct Rendered: @unchecked Sendable {
        let image: CIImage
        let preview: UIImage?
    }

    @Published var settings = CollageSettings() {
        didSet { syncCells() }
    }
    @Published var cells: [Cell] = []
    @Published var selected: Int?
    @Published var loadingCell: Int?
    @Published var isExporting = false
    @Published var toast: String?

    let store: ProjectStore

    init(store: ProjectStore) {
        self.store = store
        syncCells()
    }

    private func syncCells() {
        let count = settings.layout.cells.count
        if cells.count < count {
            cells.append(contentsOf: Array(repeating: Cell(), count: count - cells.count))
        }
        if let selected, selected >= count { self.selected = nil }
    }

    /// The edited version of a saved project.
    func use(_ project: ProjectMetadata, in index: Int) {
        let store = self.store
        let id = project.id
        load(into: index) {
            let data = try store.originalData(for: id)
            guard let source = ImageSource(data: data) else { throw LibraryError.unreadablePhoto }
            let document = (try? store.document(for: id)) ?? EditDocument()
            let proxy = source.makeProxy(maxDimension: 2400)
            return RenderPipeline().apply(document, to: proxy, scale: proxy.extent.width / max(source.pixelSize.width, 1))
        }
    }

    /// A photo straight from the library (unedited).
    func use(photoData data: Data, in index: Int) {
        load(into: index) {
            guard let source = ImageSource(data: data) else { throw LibraryError.unreadablePhoto }
            return source.makeProxy(maxDimension: 2400)
        }
    }

    private func load(into index: Int, _ work: @escaping @Sendable () throws -> CIImage) {
        loadingCell = index
        Task {
            defer { loadingCell = nil }
            do {
                let rendered = try await Task.detached(priority: .userInitiated) { () throws -> Rendered in
                    let image = RenderContext.materialize(try work(), context: RenderContext.shared)
                    let small = ImageSource.scaled(image, maxDimension: 900)
                    let preview = RenderContext.shared.createCGImage(small, from: small.extent, format: .RGBA8, colorSpace: RenderContext.sRGB)
                        .map { UIImage(cgImage: $0) }
                    return Rendered(image: image, preview: preview)
                }.value
                guard index < cells.count else { return }
                cells[index] = Cell(image: rendered.image, preview: rendered.preview, crop: CollageCrop())
                selected = index
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    func clearCell(_ index: Int) {
        guard index < cells.count else { return }
        cells[index] = Cell()
    }

    /// Renders at full size and saves to Photos.
    func save() {
        guard !isExporting else { return }
        isExporting = true
        let settings = self.settings
        let images = cells.map(\.image)
        let crops = cells.map(\.crop)
        let payload = Payload(images: images)
        Task {
            defer { isExporting = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) { () throws -> Data in
                    let canvas = CollageRenderer.render(settings, images: payload.images, crops: crops)
                    return try Exporter.export(canvas, options: ExportOptions(format: .jpeg, quality: 0.93, size: .original, metadata: .removeAll))
                }.value
                try await PhotoLibrary.save(imageData: data)
                showToast("Saved to Photos")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    private struct Payload: @unchecked Sendable {
        let images: [CIImage?]
    }

    func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toast == message { toast = nil }
        }
    }
}
