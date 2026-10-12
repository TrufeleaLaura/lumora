import CoreImage
import Foundation

/// A decoded source photo. `original` is upright (EXIF orientation applied) with its origin at (0, 0).
public final class ImageSource {
    public let original: CIImage
    public let properties: [String: Any]

    public init?(data: Data) {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        self.original = ImageSource.normalized(image)
        self.properties = image.properties
    }

    public init(image: CIImage) {
        self.original = ImageSource.normalized(image)
        self.properties = image.properties
    }

    public var pixelSize: CGSize { original.extent.size }

    /// A downscaled, pre-rendered copy for fast interactive previews. Rendered once into a
    /// half-float bitmap so later slider changes don't re-decode the full-resolution file.
    public func makeProxy(maxDimension: CGFloat, context: CIContext = RenderContext.shared) -> CIImage {
        let extent = original.extent
        let scale = min(1, maxDimension / max(extent.width, extent.height))
        var image = original
        if scale < 1 {
            image = image.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1.0,
            ])
        }
        image = ImageSource.normalized(image)
        let rect = CGRect(origin: .zero, size: CGSize(width: floor(image.extent.width), height: floor(image.extent.height)))
        guard let cgImage = context.createCGImage(image, from: rect, format: .RGBAh, colorSpace: RenderContext.linearDisplayP3) else {
            return image.cropped(to: rect)
        }
        return CIImage(cgImage: cgImage)
    }

    private static func normalized(_ image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.minX != 0 || extent.minY != 0 else { return image }
        return image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
    }
}
