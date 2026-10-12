import CoreImage
import Foundation

/// Results of the haze analysis used by Dehaze.
public struct HazeAnalysis {
    /// Low-resolution guided coefficients mapping perceptual luminance to transmission.
    public let coefficients: CIImage
    /// Atmospheric light color (linear RGB).
    public let airlight: SIMD3<Float>
}

/// Per-photo analysis computed once from the unedited preview and reused for every render
/// (preview, zoomed refinement and export). Everything is resolution-independent.
/// Properties compute lazily on first use and are thread-safe.
public final class ImageAnalysis: @unchecked Sendable {
    private let source: CIImage
    private let context: CIContext
    private let lock = NSLock()
    private var cachedToneBase: CIImage?
    private var cachedClarityBase: CIImage?
    private var cachedHaze: HazeAnalysis?

    public init(image: CIImage, context: CIContext = RenderContext.analysis) {
        self.source = image
        self.context = context
    }

    /// Local average brightness (guided-filter coefficients of log luminance, large radius).
    public var toneBase: CIImage {
        lock.lock()
        defer { lock.unlock() }
        if let cachedToneBase { return cachedToneBase }
        let result = Self.logLuminanceCoefficients(source, workingSize: 512, radiusFraction: 0.03, eps: 0.12, context: context)
        cachedToneBase = result
        return result
    }

    /// Mid-scale local brightness for Clarity (smaller radius).
    public var clarityBase: CIImage {
        lock.lock()
        defer { lock.unlock() }
        if let cachedClarityBase { return cachedClarityBase }
        let result = Self.logLuminanceCoefficients(source, workingSize: 1024, radiusFraction: 0.008, eps: 0.05, context: context)
        cachedClarityBase = result
        return result
    }

    public var haze: HazeAnalysis {
        lock.lock()
        defer { lock.unlock() }
        if let cachedHaze { return cachedHaze }
        let result = Self.computeHaze(source, context: context)
        cachedHaze = result
        return result
    }

    /// Computes everything in advance (call from a background task).
    public func prewarm() {
        _ = toneBase
        _ = clarityBase
        _ = haze
    }

    // MARK: - Computation

    private static func logLuminanceCoefficients(_ image: CIImage, workingSize: CGFloat, radiusFraction: CGFloat, eps: Float, context: CIContext) -> CIImage {
        let pair = Kernels.logLumaPair.apply(image)
        let small = ImageSource.scaled(pair, maxDimension: workingSize)
        let radius = max(2, radiusFraction * max(small.extent.width, small.extent.height))
        let coefficients = GuidedFilter.selfCoefficients(pair: small, radius: radius, eps: eps)
        return RenderContext.materialize(coefficients, context: context)
    }

    private static func computeHaze(_ image: CIImage, context: CIContext) -> HazeAnalysis {
        let small = ImageSource.scaled(image, maxDimension: 512)
        let extent = small.extent
        let longSide = max(extent.width, extent.height)
        let dark = Kernels.darkChannel.apply(small)
        let darkMin = dark.clampedToExtent()
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: max(2, longSide * 0.006)])
            .cropped(to: extent)

        // Atmospheric light: average color of the haziest 0.2 % (largest dark-channel values).
        let darkPixels = RenderContext.readFloats(darkMin, context: context)
        let colorPixels = RenderContext.readFloats(small, context: context)
        let count = darkPixels.width * darkPixels.height
        var airlight = SIMD3<Float>(0.8, 0.8, 0.8)
        if count > 0, colorPixels.pixels.count == count * 4 {
            var indices = Array(0..<count)
            indices.sort { darkPixels.pixels[$0 * 4] > darkPixels.pixels[$1 * 4] }
            let top = max(1, count / 500)
            var sum = SIMD3<Float>(0, 0, 0)
            for index in indices.prefix(top) {
                sum += SIMD3(colorPixels.pixels[index * 4], colorPixels.pixels[index * 4 + 1], colorPixels.pixels[index * 4 + 2])
            }
            airlight = (sum / Float(top)).clamped(lowerBound: SIMD3(repeating: 0.05), upperBound: SIMD3(repeating: 4))
        }
        let airlightMax = max(airlight.x, max(airlight.y, airlight.z))

        let transmission = Kernels.transmission.apply(darkMin, airlightMax)
        let guide = Kernels.perceptualLuma.apply(small)
        // Small radius + small eps: transmission follows luminance edges closely (no halos).
        let coefficients = GuidedFilter.coefficients(guide: guide, target: transmission, radius: max(2, longSide * 0.01), eps: 0.0001)
        return HazeAnalysis(coefficients: RenderContext.materialize(coefficients, context: context), airlight: airlight)
    }
}
