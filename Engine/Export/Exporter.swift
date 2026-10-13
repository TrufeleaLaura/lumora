import CoreImage
import Foundation
import ImageIO
import LumoraCore
import UniformTypeIdentifiers

public enum ExportError: Error, LocalizedError {
    case encodingFailed(ExportFormat)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let format):
            return "Couldn't encode the image as \(format.displayName)."
        }
    }
}

public enum Exporter {
    /// Renders and encodes an edited image with the chosen format, size and metadata policy.
    /// `sourceProperties` is the original file's metadata (EXIF, GPS, …).
    public static func export(
        _ image: CIImage,
        options: ExportOptions,
        sourceProperties: [String: Any] = [:],
        context: CIContext = RenderContext.shared
    ) throws -> Data {
        var output = image
        if let maxEdge = options.size.maxLongEdge {
            output = ImageSource.scaled(output, maxDimension: CGFloat(maxEdge))
        } else if options.size == .enlarged {
            output = enlarged(output)
        }
        output = ImageSource.normalized(output)
        let rect = CGRect(origin: .zero, size: CGSize(width: floor(output.extent.width), height: floor(output.extent.height)))
        output = output.cropped(to: rect)
        output = output.settingProperties(metadata(from: sourceProperties, policy: options.metadata))
        return try encode(output, format: options.format, quality: options.quality, context: context)
    }

    /// Doubles the size: Lanczos resampling, then edge-aware sharpening at the new scale so
    /// edges stay crisp without halos (a classic, model-free upscaler).
    public static func enlarged(_ image: CIImage) -> CIImage {
        let normalized = ImageSource.normalized(image)
        let extent = normalized.extent
        let upscaled = normalized.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: 2.0, kCIInputAspectRatioKey: 1.0])
        let target = CGRect(x: 0, y: 0, width: (extent.width * 2).rounded(.down), height: (extent.height * 2).rounded(.down))
        var detail = DetailSettings()
        detail.sharpening = 70
        detail.sharpenRadius = 1.4
        detail.sharpenDetail = 20
        detail.sharpenMasking = 35
        return RenderPipeline().applySharpening(detail, to: upscaled.cropped(to: target), scale: 1)
    }

    /// Encodes an image (Display P3) without resizing. Metadata comes from `image.properties`.
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
        case .tiff:
            data = context.tiffRepresentation(of: image, format: .RGBA16, colorSpace: colorSpace, options: [:])
        }
        guard let data else { throw ExportError.encodingFailed(format) }
        return data
    }

    /// File extension matching encoded image data (e.g. "heic" or "jpg").
    public static func fileExtension(forEncoded data: Data) -> String? {
        guard let type = ImageSource.typeIdentifier(of: data), let utType = UTType(type) else { return nil }
        return utType.preferredFilenameExtension
    }

    /// Small JPEG for project thumbnails.
    public static func thumbnailJPEG(_ image: CIImage, maxDimension: CGFloat = 480, context: CIContext = RenderContext.shared) -> Data? {
        let scaled = ImageSource.scaled(image, maxDimension: maxDimension)
        let rect = CGRect(origin: .zero, size: CGSize(width: floor(scaled.extent.width), height: floor(scaled.extent.height)))
        return try? encode(scaled.cropped(to: rect).settingProperties([:]), format: .jpeg, quality: 0.8, context: context)
    }

    /// Metadata to embed in an exported file. Pixels are already upright, so orientation is reset;
    /// size fields are dropped (the encoder writes the real ones).
    public static func metadata(from source: [String: Any], policy: MetadataPolicy) -> [String: Any] {
        let orientation = kCGImagePropertyOrientation as String
        guard policy != .removeAll else {
            return [orientation: 1]
        }
        var result = source
        for key in [
            kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyDepth,
            kCGImagePropertyHasAlpha, kCGImagePropertyProfileName, kCGImagePropertyColorModel,
        ] {
            result.removeValue(forKey: key as String)
        }
        result[orientation] = 1

        if var tiff = result[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            tiff[kCGImagePropertyTIFFSoftware as String] = "Lumora"
            result[kCGImagePropertyTIFFDictionary as String] = tiff
        } else {
            result[kCGImagePropertyTIFFDictionary as String] = [kCGImagePropertyTIFFSoftware as String: "Lumora"]
        }
        if var exif = result[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension as String)
            exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension as String)
            result[kCGImagePropertyExifDictionary as String] = exif
        }
        if policy == .removeLocation {
            result.removeValue(forKey: kCGImagePropertyGPSDictionary as String)
        }
        return result
    }
}
