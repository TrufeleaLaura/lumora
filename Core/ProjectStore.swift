import Foundation

/// Information about one saved edit project.
public struct ProjectMetadata: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    /// File name of the stored original inside the project folder, e.g. "original.heic".
    public var originalFileName: String
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(id: UUID = UUID(), createdAt: Date = Date(), modifiedAt: Date = Date(), originalFileName: String, pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.originalFileName = originalFileName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public enum ProjectStoreError: Error, LocalizedError {
    case projectNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .projectNotFound:
            return "This project no longer exists."
        }
    }
}

/// Saves edit projects on disk. Each project is a folder:
/// `meta.json`, `document.json`, `original.<ext>` (an untouched copy of the photo) and `thumbnail.jpg`.
public final class ProjectStore: @unchecked Sendable {
    public let rootURL: URL
    private let fileManager = FileManager.default

    public init(rootURL: URL) {
        self.rootURL = rootURL
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    /// The app's standard store in Application Support/Projects.
    public static func makeDefault() -> ProjectStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return ProjectStore(rootURL: base.appendingPathComponent("Projects", isDirectory: true))
    }

    // MARK: - Paths

    public func folderURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func thumbnailURL(for id: UUID) -> URL {
        folderURL(for: id).appendingPathComponent("thumbnail.jpg")
    }

    private func metadataURL(for id: UUID) -> URL {
        folderURL(for: id).appendingPathComponent("meta.json")
    }

    private func documentURL(for id: UUID) -> URL {
        folderURL(for: id).appendingPathComponent("document.json")
    }

    // MARK: - Queries

    /// All projects, most recently edited first.
    public func list() -> [ProjectMetadata] {
        guard let folders = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else {
            return []
        }
        let projects = folders.compactMap { folder -> ProjectMetadata? in
            let url = folder.appendingPathComponent("meta.json")
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? Self.decoder.decode(ProjectMetadata.self, from: data)
        }
        return projects.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func metadata(for id: UUID) throws -> ProjectMetadata {
        guard let data = try? Data(contentsOf: metadataURL(for: id)) else {
            throw ProjectStoreError.projectNotFound(id)
        }
        return try Self.decoder.decode(ProjectMetadata.self, from: data)
    }

    public func originalData(for id: UUID) throws -> Data {
        let meta = try metadata(for: id)
        return try Data(contentsOf: folderURL(for: id).appendingPathComponent(meta.originalFileName))
    }

    public func document(for id: UUID) throws -> EditDocument {
        guard let data = try? Data(contentsOf: documentURL(for: id)) else {
            return EditDocument()
        }
        return try EditDocument.decode(from: data)
    }

    // MARK: - Mutations

    /// Creates a project holding a copy of the original photo data.
    @discardableResult
    public func create(originalData: Data, fileExtension: String, pixelWidth: Int, pixelHeight: Int, document: EditDocument = EditDocument()) throws -> ProjectMetadata {
        let ext = fileExtension.isEmpty ? "jpg" : fileExtension.lowercased()
        let meta = ProjectMetadata(originalFileName: "original.\(ext)", pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        let folder = folderURL(for: meta.id)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try originalData.write(to: folder.appendingPathComponent(meta.originalFileName), options: .atomic)
        try document.jsonData().write(to: documentURL(for: meta.id), options: .atomic)
        try writeMetadata(meta)
        return meta
    }

    public func save(document: EditDocument, for id: UUID) throws {
        var meta = try metadata(for: id)
        try document.jsonData().write(to: documentURL(for: id), options: .atomic)
        meta.modifiedAt = Date()
        try writeMetadata(meta)
    }

    public func saveThumbnail(_ jpegData: Data, for id: UUID) throws {
        try jpegData.write(to: thumbnailURL(for: id), options: .atomic)
    }

    @discardableResult
    public func duplicate(_ id: UUID) throws -> ProjectMetadata {
        let source = try metadata(for: id)
        var copy = source
        copy.id = UUID()
        copy.createdAt = Date()
        copy.modifiedAt = Date()
        try fileManager.copyItem(at: folderURL(for: id), to: folderURL(for: copy.id))
        try writeMetadata(copy)
        return copy
    }

    public func delete(_ id: UUID) throws {
        let folder = folderURL(for: id)
        if fileManager.fileExists(atPath: folder.path) {
            try fileManager.removeItem(at: folder)
        }
    }

    private func writeMetadata(_ meta: ProjectMetadata) throws {
        try Self.encoder.encode(meta).write(to: metadataURL(for: meta.id), options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
