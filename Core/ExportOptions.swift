import Foundation

public enum ExportFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case heic
    case jpeg
    case png
    case tiff

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .heic: return "HEIC"
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .tiff: return "TIFF 16-bit"
        }
    }

    public var fileExtension: String {
        switch self {
        case .heic: return "heic"
        case .jpeg: return "jpg"
        case .png: return "png"
        case .tiff: return "tiff"
        }
    }

    public var supportsQuality: Bool {
        self == .heic || self == .jpeg
    }
}

public enum ExportSize: String, CaseIterable, Codable, Sendable, Identifiable {
    case original
    /// Twice the original size (detail-preserving upscale).
    case enlarged
    case large
    case medium
    case social

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .original: return "Original"
        case .enlarged: return "Enlarge 2×"
        case .large: return "4096 px"
        case .medium: return "2048 px"
        case .social: return "1080 px"
        }
    }

    /// Maximum length of the long edge in pixels, or nil for the original size.
    public var maxLongEdge: Double? {
        switch self {
        case .original, .enlarged: return nil
        case .large: return 4096
        case .medium: return 2048
        case .social: return 1080
        }
    }
}

public enum MetadataPolicy: String, CaseIterable, Codable, Sendable, Identifiable {
    case keepAll
    case removeLocation
    case removeAll

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .keepAll: return "Keep all"
        case .removeLocation: return "Remove location"
        case .removeAll: return "Remove all"
        }
    }
}

public struct ExportOptions: Codable, Equatable, Sendable {
    public var format: ExportFormat
    /// 0...1, used by HEIC and JPEG.
    public var quality: Double
    public var size: ExportSize
    public var metadata: MetadataPolicy

    public init(format: ExportFormat = .heic, quality: Double = 0.92, size: ExportSize = .original, metadata: MetadataPolicy = .removeLocation) {
        self.format = format
        self.quality = quality
        self.size = size
        self.metadata = metadata
    }
}
