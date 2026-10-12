import Foundation

/// A user-saved set of adjustments ("preset").
public struct UserPreset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var document: EditDocument

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), document: EditDocument) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.document = document
    }
}

/// Saves user presets as one JSON file.
public final class PresetStore: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    public static let shared: PresetStore = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return PresetStore(fileURL: base.appendingPathComponent("Presets/presets.json"))
    }()

    public func list() -> [UserPreset] {
        lock.lock()
        defer { lock.unlock() }
        return load()
    }

    @discardableResult
    public func save(name: String, document: EditDocument) throws -> UserPreset {
        lock.lock()
        defer { lock.unlock() }
        var presets = load()
        // Presets never carry crop/rotation (those belong to a specific photo).
        let preset = UserPreset(name: name, document: document.adjustmentsOnly(keeping: GeometrySettings()))
        presets.append(preset)
        try write(presets)
        return preset
    }

    public func delete(_ id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        try write(load().filter { $0.id != id })
    }

    private func load() -> [UserPreset] {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Decode each preset's document leniently so older presets keep working.
        return raw.compactMap { entry -> UserPreset? in
            guard let idString = entry["id"] as? String, let id = UUID(uuidString: idString),
                  let name = entry["name"] as? String,
                  let documentObject = entry["document"],
                  let documentData = try? JSONSerialization.data(withJSONObject: documentObject),
                  let document = try? EditDocument.decode(from: documentData) else { return nil }
            let created = (entry["createdAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
            return UserPreset(id: id, name: name, createdAt: created, document: document)
        }
    }

    private func write(_ presets: [UserPreset]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(presets).write(to: fileURL, options: .atomic)
    }
}

/// Metadata of an imported .cube LUT.
public struct ImportedLUT: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var size: Int
    public var createdAt: Date

    public init(id: String, name: String, size: Int, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.size = size
        self.createdAt = createdAt
    }

    /// The look that applies this LUT.
    public var look: Look {
        Look(id: id, name: name, pack: .custom, recipe: LookRecipe(), lutID: id)
    }
}

/// Stores imported LUTs (the original .cube text plus an index) and caches parsed tables.
public final class LUTStore: @unchecked Sendable {
    public let rootURL: URL
    private let lock = NSLock()
    private var cache: [String: CubeLUT] = [:]

    public init(rootURL: URL) {
        self.rootURL = rootURL
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    public static let shared: LUTStore = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return LUTStore(rootURL: base.appendingPathComponent("LUTs", isDirectory: true))
    }()

    private var indexURL: URL { rootURL.appendingPathComponent("index.json") }

    public func list() -> [ImportedLUT] {
        lock.lock()
        defer { lock.unlock() }
        return loadIndex()
    }

    /// Parses and stores a .cube file. Throws if the file isn't a valid 3D LUT.
    @discardableResult
    public func importCube(text: String, name: String) throws -> ImportedLUT {
        let lut = try CubeLUT.parse(text, fallbackTitle: name)
        lock.lock()
        defer { lock.unlock() }
        let entry = ImportedLUT(id: "lut.\(UUID().uuidString)", name: name, size: lut.size)
        try text.write(to: rootURL.appendingPathComponent("\(entry.id).cube"), atomically: true, encoding: .utf8)
        var index = loadIndex()
        index.append(entry)
        try writeIndex(index)
        cache[entry.id] = lut
        return entry
    }

    public func lut(id: String) -> CubeLUT? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[id] { return cached }
        guard let text = try? String(contentsOf: rootURL.appendingPathComponent("\(id).cube"), encoding: .utf8),
              let lut = try? CubeLUT.parse(text) else { return nil }
        cache[id] = lut
        return lut
    }

    public func delete(_ id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: rootURL.appendingPathComponent("\(id).cube"))
        cache[id] = nil
        try writeIndex(loadIndex().filter { $0.id != id })
    }

    private func loadIndex() -> [ImportedLUT] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ImportedLUT].self, from: data)) ?? []
    }

    private func writeIndex(_ index: [ImportedLUT]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(index).write(to: indexURL, options: .atomic)
    }
}
