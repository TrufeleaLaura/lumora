import CoreImage
import Foundation
import ImageIO

public enum ExportFormat: String, CaseIterable, Codable, Sendable {
    case heic
    case jpeg
    case png

    public var fileExtension: String {
        switch self {
        case .heic: return "heic"
        case .jpeg: return "jpg"
        case .png: return "png"
        }
    }
}

public enum ExportError: Error, LocalizedError {
    case encodingFailed(ExportFormat)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let format):
            return "Couldn't encode the image as \(format.rawValue.uppercased())."
        }
    }
}

public enum Exporter {
    /// Encodes a rendered image. Wide-color (Display P3) output for HEIC/JPEG/PNG.
    public static func encode(
        _ image: CIImage,
        format: ExportFormat,
        quality: Double = 0.92,
        context: CIContext = RenderContext.shared
    ) throws -> Data {
        let colorSpace = RenderContext.displayP3
        let qualityKey = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        let options: [CIImageRepresentationOption: Any] = [qualityKey: quality]

        let data: Data?
        switch format {
        case .heic:
            data = context.heifRepresentation(of: image, format: .RGBA8, colorSpace: colorSpace, options: options)
        case .jpeg:
            data = context.jpegRepresentation(of: image, colorSpace: colorSpace, options: options)
        case .png:
            data = context.pngRepresentation(of: image, format: .RGBA8, colorSpace: colorSpace, options: [:])
        }
        guard let data else { throw ExportError.encodingFailed(format) }
        return data
    }
}
