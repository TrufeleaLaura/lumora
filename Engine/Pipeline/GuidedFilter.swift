import CoreImage
import Foundation

/// Edge-preserving smoothing (He et al., "Guided Image Filtering") built from box blurs.
/// Coefficients are usually computed at low resolution and upsampled ("fast guided filter"),
/// then applied per pixel at full resolution, which keeps edges crisp.
enum GuidedFilter {
    /// Box blur that keeps the extent (edges clamped).
    static func box(_ image: CIImage, radius: CGFloat) -> CIImage {
        let extent = image.extent
        return image.clampedToExtent()
            .applyingFilter("CIBoxBlur", parameters: [kCIInputRadiusKey: max(radius, 1)])
            .cropped(to: extent)
    }

    /// Gaussian blur that keeps the extent (edges clamped).
    static func gaussian(_ image: CIImage, radius: CGFloat) -> CIImage {
        guard radius > 0.05 else { return image }
        let extent = image.extent
        return image.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
    }

    /// Self-guided coefficients (mean a, mean b) from a pair image (I, I², 0).
    static func selfCoefficients(pair: CIImage, radius: CGFloat, eps: Float) -> CIImage {
        let means = box(pair, radius: radius)
        let coefficients = Kernels.guidedSelfCoefficients.apply(means, eps)
        return box(coefficients, radius: radius)
    }

    /// Coefficients for smoothing `target` guided by `guide` (both single-channel in .r).
    static func coefficients(guide: CIImage, target: CIImage, radius: CGFloat, eps: Float) -> CIImage {
        let pack = Kernels.guidedPack.apply(guide, target)
        let square = Kernels.guidedPackSquare.apply(guide)
        let means = box(pack, radius: radius)
        let meanSquares = box(square, radius: radius)
        let coefficients = Kernels.guidedCoefficients.apply(means, meanSquares, eps)
        return box(coefficients, radius: radius)
    }

    /// Stretches low-resolution coefficients over `extent`.
    static func upsample(_ coefficients: CIImage, to extent: CGRect) -> CIImage {
        let source = coefficients.extent
        guard source.width > 0, source.height > 0 else { return coefficients }
        let transform = CGAffineTransform(translationX: -source.minX, y: -source.minY)
            .concatenating(CGAffineTransform(scaleX: extent.width / source.width, y: extent.height / source.height))
            .concatenating(CGAffineTransform(translationX: extent.minX, y: extent.minY))
        return coefficients.clampedToExtent().transformed(by: transform).cropped(to: extent)
    }

    /// Identity coefficients (a = 1, b = 0): "no smoothing".
    static func identity(extent: CGRect) -> CIImage {
        CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: extent)
    }
}
