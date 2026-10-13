import CoreImage
import LumoraCore
import LumoraEngine
import SwiftUI
import UIKit

enum PreviewSettings {
    /// Long edge of the interactive preview proxy, in pixels.
    static let proxyDimension: CGFloat = 2560
}

enum LibraryError: Error, LocalizedError {
    case unreadablePhoto

    var errorDescription: String? {
        switch self {
        case .unreadablePhoto:
            return "This photo couldn't be opened."
        }
    }
}

/// Saved projects for the library screen, plus importing/opening photos into editor sessions.
@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var projects: [ProjectMetadata] = []
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?

    let store = ProjectStore.makeDefault()
    private var thumbnailCache: [String: UIImage] = [:]

    /// Result of background preparation. Core Image values are immutable and thread-safe.
    private struct Prepared: @unchecked Sendable {
        let projectID: UUID
        let source: ImageSource
        let proxy: CIImage
        let document: EditDocument
    }

    /// Projects in the planned feed order (top-left first).
    @Published private(set) var feed: [ProjectMetadata] = []

    func reload() {
        projects = store.list()
        feed = ProjectStore.feed(projects, order: store.feedOrder())
    }

    /// Moves a project to another project's place in the feed plan.
    func moveInFeed(_ id: UUID, to target: UUID) {
        guard id != target, let from = feed.firstIndex(where: { $0.id == id }), let to = feed.firstIndex(where: { $0.id == target }) else { return }
        var items = feed
        let item = items.remove(at: from)
        items.insert(item, at: to)
        feed = items
        store.saveFeedOrder(items.map(\.id))
    }

    func thumbnail(for project: ProjectMetadata) -> UIImage? {
        let key = "\(project.id.uuidString)-\(project.modifiedAt.timeIntervalSince1970)"
        if let cached = thumbnailCache[key] {
            return cached
        }
        guard let image = UIImage(contentsOfFile: store.thumbnailURL(for: project.id).path) else { return nil }
        thumbnailCache[key] = image
        return image
    }

    /// Creates a new project from photo data and opens it.
    func importPhoto(data: Data) async -> EditorSession? {
        let store = self.store
        return await prepareSession {
            guard let source = ImageSource(data: data) else { throw LibraryError.unreadablePhoto }
            let meta = try store.create(
                originalData: data,
                fileExtension: source.preferredFileExtension,
                pixelWidth: Int(source.pixelSize.width),
                pixelHeight: Int(source.pixelSize.height)
            )
            let proxy = source.makeProxy(maxDimension: PreviewSettings.proxyDimension)
            if let thumbnail = Exporter.thumbnailJPEG(proxy) {
                try? store.saveThumbnail(thumbnail, for: meta.id)
            }
            return Prepared(projectID: meta.id, source: source, proxy: proxy, document: EditDocument())
        }
    }

    /// Starts an edit of the bundled sample photo (for trying the app, and for UI tests).
    func openSample() async -> EditorSession? {
        guard let url = Bundle.main.url(forResource: "SamplePhoto", withExtension: "jpg"),
              let data = try? Data(contentsOf: url) else { return nil }
        return await importPhoto(data: data)
    }

    /// Re-opens a saved project with its edits.
    func open(_ project: ProjectMetadata) async -> EditorSession? {
        let store = self.store
        let id = project.id
        return await prepareSession {
            let data = try store.originalData(for: id)
            guard let source = ImageSource(data: data) else { throw LibraryError.unreadablePhoto }
            let document = try store.document(for: id)
            let proxy = source.makeProxy(maxDimension: PreviewSettings.proxyDimension)
            return Prepared(projectID: id, source: source, proxy: proxy, document: document)
        }
    }

    /// Pastes copied edits onto several projects (each keeps its own crop/rotation) and
    /// refreshes their thumbnails.
    func pasteEdits(_ document: EditDocument, to ids: [UUID]) async {
        isBusy = true
        defer { isBusy = false }
        let store = self.store
        await Task.detached(priority: .userInitiated) {
            for id in ids {
                guard let data = try? store.originalData(for: id), let source = ImageSource(data: data) else { continue }
                let existing = (try? store.document(for: id)) ?? EditDocument()
                let updated = document.adjustmentsOnly(keeping: existing.geometry)
                try? store.save(document: updated, for: id)
                let small = source.makeProxy(maxDimension: 720)
                let rendered = RenderPipeline().apply(updated, to: small, scale: small.extent.width / max(source.pixelSize.width, 1))
                if let thumbnail = Exporter.thumbnailJPEG(rendered) {
                    try? store.saveThumbnail(thumbnail, for: id)
                }
            }
        }.value
        reload()
    }

    func delete(_ ids: [UUID]) {
        for id in ids {
            try? store.delete(id)
        }
        reload()
    }

    func duplicate(_ project: ProjectMetadata) {
        do {
            try store.duplicate(project.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ project: ProjectMetadata) {
        do {
            try store.delete(project.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareSession(_ work: @escaping @Sendable () throws -> Prepared) async -> EditorSession? {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let prepared = try await Task.detached(priority: .userInitiated) {
                try work()
            }.value
            reload()
            return EditorSession(
                projectID: prepared.projectID,
                source: prepared.source,
                proxy: prepared.proxy,
                document: prepared.document,
                store: store
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
