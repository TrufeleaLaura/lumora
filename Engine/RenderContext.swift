import CoreImage
import Metal

/// Shared GPU and Core Image state. Creating a CIContext is expensive, so the app uses a few shared ones.
public enum RenderContext {
    public static let device: MTLDevice? = MTLCreateSystemDefaultDevice()

    /// Linear, extended-range working space: edits happen in scene-linear light, in half floats.
    public static let workingColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    public static let linearSRGB = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    public static let linearDisplayP3 = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
    public static let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!
    public static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Rendering context for previews and exports (half-float intermediates).
    public static let shared: CIContext = makeContext(format: .RGBAh)

    /// Full 32-bit float context for analysis passes (guided filters need the precision).
    public static let analysis: CIContext = makeContext(format: .RGBAf)

    private static func makeContext(format: CIFormat) -> CIContext {
        let options: [CIContextOption: Any] = [
            .workingColorSpace: workingColorSpace,
            .workingFormat: NSNumber(value: format.rawValue),
            // Every edit builds a new graph; caching old intermediates only costs memory.
            .cacheIntermediates: false,
        ]
        if let device {
            return CIContext(mtlDevice: device, options: options)
        }
        return CIContext(options: options)
    }

    /// Renders a data image (not a picture) into a bitmap-backed image, without color management.
    /// Half floats by default (masks, patches); pass `.RGBAf` where full precision matters.
    public static func materialize(_ image: CIImage, context: CIContext = analysis, format: CIFormat = .RGBAh) -> CIImage {
        let extent = image.extent.integral
        guard let cgImage = context.createCGImage(image, from: extent, format: format, colorSpace: nil) else {
            return image
        }
        return CIImage(cgImage: cgImage, options: [.colorSpace: NSNull()])
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    /// Reads a data image into a float array (RGBA per pixel, rows top-down), without color management.
    public static func readFloats(_ image: CIImage, context: CIContext = analysis) -> (pixels: [Float], width: Int, height: Int) {
        let extent = image.extent.integral
        // Guard against infinite or absurd extents (would trap or exhaust memory).
        guard !extent.isInfinite, !extent.isNull, extent.width > 0, extent.height > 0,
              extent.width * extent.height < 80_000_000 else { return ([], 0, 0) }
        let width = Int(extent.width)
        let height = Int(extent.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            context.render(image, toBitmap: buffer.baseAddress!, rowBytes: width * 16, bounds: extent, format: .RGBAf, colorSpace: nil)
        }
        return (pixels, width, height)
    }
}
