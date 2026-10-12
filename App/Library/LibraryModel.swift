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

    func reload() {
        projects = store.list()
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
