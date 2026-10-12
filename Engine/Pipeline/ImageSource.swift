import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A decoded source photo. `original` is upright (EXIF orientation applied) with its origin at (0, 0).
/// RAW files (DNG, ProRAW, camera RAW) are developed with `CIRAWFilter`.
public final class ImageSource: @unchecked Sendable {
    public let original: CIImage
    /// Image metadata (EXIF, TIFF, GPS, …) as read from the file.
    public let properties: [String: Any]
    /// Uniform type of the file, e.g. "public.heic" or "com.adobe.raw-image".
    public let typeIdentifier: String?
    public let isRAW: Bool

    public init?(data: Data) {
        let type = ImageSource.typeIdentifier(of: data)
        let utType = type.flatMap { UTType($0) }
        let raw = utType?.conforms(to: .rawImage) ?? false

        var decoded: CIImage?
        var developedAsRAW = false
        if raw, let rawFilter = CIRAWFilter(imageData: data, identifierHint: type), let output = rawFilter.outputImage {
            decoded = output
            developedAsRAW = true
        }
        if decoded == nil {
            decoded = CIImage(data: data, options: [.applyOrientationProperty: true])
        }
        guard let image = decoded, !image.extent.isInfinite, image.extent.width > 0 else { return nil }

        self.original = ImageSource.normalized(image)
        self.properties = ImageSource.fileProperties(of: data) ?? image.properties
        self.typeIdentifier = type
        self.isRAW = developedAsRAW
    }

    public init(image: CIImage, properties: [String: Any] = [:]) {
        self.original = ImageSource.normalized(image)
        self.properties = properties.isEmpty ? image.properties : properties
        self.typeIdentifier = nil
        self.isRAW = false
    }

    public var pixelSize: CGSize { original.extent.size }

    /// Preferred file extension for storing the original ("heic", "jpg", "dng", …).
    public var preferredFileExtension: String {
        guard let typeIdentifier, let type = UTType(typeIdentifier) else { return "jpg" }
        return type.preferredFilenameExtension ?? "jpg"
    }

    /// A downscaled, pre-rendered copy for fast interactive previews. Rendered once into a
    /// half-float bitmap so later slider changes don't re-decode the full-resolution file.
    public func makeProxy(maxDimension: CGFloat, context: CIContext = RenderContext.shared) -> CIImage {
        let image = ImageSource.scaled(original, maxDimension: maxDimension)
        let rect = CGRect(origin: .zero, size: CGSize(width: floor(image.extent.width), height: floor(image.extent.height)))
        guard let cgImage = context.createCGImage(image, from: rect, format: .RGBAh, colorSpace: RenderContext.linearDisplayP3) else {
            return image.cropped(to: rect)
        }
        return CIImage(cgImage: cgImage)
    }

    /// High-quality downscale so the long edge is at most `maxDimension` (never upscales).
    public static func scaled(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let extent = image.extent
        let scale = min(1, maxDimension / max(extent.width, extent.height))
        guard scale < 1 else { return normalized(image) }
        let output = image.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: 1.0,
        ])
        return normalized(output)
    }

    static func normalized(_ image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.minX != 0 || extent.minY != 0 else { return image }
        return image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
    }

    public static func typeIdentifier(of data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { return nil }
        return type as String
    }

    static func fileProperties(of data: Data) -> [String: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return nil }
        return properties
    }
}
