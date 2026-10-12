import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Simple measurements on images (used by tests now, by Auto tone later).
public enum ImageStats {
    /// Average linear RGBA over the image.
    public static func averageColor(of image: CIImage, context: CIContext = RenderContext.shared) -> SIMD4<Float> {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = image.extent
        guard let output = filter.outputImage else { return .zero }

        var pixel = [Float](repeating: 0, count: 4)
        let bounds = CGRect(x: output.extent.minX, y: output.extent.minY, width: 1, height: 1)
        pixel.withUnsafeMutableBytes { buffer in
            context.render(
                output,
                toBitmap: buffer.baseAddress!,
                rowBytes: 4 * MemoryLayout<Float>.size,
                bounds: bounds,
                format: .RGBAf,
                colorSpace: RenderContext.linearSRGB
            )
        }
        return SIMD4(pixel[0], pixel[1], pixel[2], pixel[3])
    }

    /// Mean and standard deviation of perceptual luminance (0...1) — a measure of local contrast/noise.
    public static func perceptualLuminanceStats(of image: CIImage, context: CIContext = RenderContext.analysis) -> (mean: Float, deviation: Float) {
        let pair = Kernels.perceptualLumaPair.apply(image)
        let average = averageColor(of: pair, context: context)
        let variance = max(average.y - average.x * average.x, 0)
        return (average.x, variance.squareRoot())
    }

    /// Average linear luminance (Rec. 709 weights).
    public static func averageLuminance(of image: CIImage, context: CIContext = RenderContext.shared) -> Float {
        let c = averageColor(of: image, context: context)
        return 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
    }
}
