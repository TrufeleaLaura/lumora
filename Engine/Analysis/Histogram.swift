import CoreImage
import Foundation
import LumoraCore

/// Brightness distribution of an image (perceptual 0...1), per channel and for luminance.
public struct HistogramData: Equatable, Sendable {
    public var red: [Float]
    public var green: [Float]
    public var blue: [Float]
    public var luma: [Float]
    /// Fractions of pixels that are pure black or clipped white in some channel.
    public var shadowClip: Float
    public var highlightClip: Float
}

public enum Histogram {
    /// Histogram of `image` (measured on a small copy), each curve scaled to a peak of 1.
    public static func compute(_ image: CIImage, bins: Int = 64, context: CIContext = RenderContext.analysis) -> HistogramData {
        let small = ImageSource.scaled(image, maxDimension: 256)
        let data = RenderContext.readFloats(small, context: context)
        var red = [Float](repeating: 0, count: bins), green = red, blue = red, luma = red
        var shadows = 0, highlights = 0
        let count = data.width * data.height
        func bin(_ value: Float) -> Int { min(bins - 1, max(0, Int(pow(max(value, 0), 1 / 2.2) * Float(bins)))) }
        for i in 0..<count {
            let r = data.pixels[i * 4], g = data.pixels[i * 4 + 1], b = data.pixels[i * 4 + 2]
            red[bin(r)] += 1
            green[bin(g)] += 1
            blue[bin(b)] += 1
            luma[bin(0.2126 * r + 0.7152 * g + 0.0722 * b)] += 1
            if max(r, max(g, b)) >= 0.999 { highlights += 1 }
            if max(r, max(g, b)) <= 0.0015 { shadows += 1 }
        }
        func normalized(_ values: [Float]) -> [Float] {
            // Ignore the extreme end bins when scaling so clipped spikes don't flatten the curve.
            let peak = max(values.dropFirst().dropLast().max() ?? 1, 1)
            return values.map { min($0 / peak, 1) }
        }
        let total = Float(max(count, 1))
        return HistogramData(
            red: normalized(red), green: normalized(green), blue: normalized(blue), luma: normalized(luma),
            shadowClip: Float(shadows) / total, highlightClip: Float(highlights) / total
        )
    }

    /// The photo with clipped highlights in red and crushed shadows in blue.
    public static func clippingOverlay(_ image: CIImage) -> CIImage {
        Kernels.clipping.apply(image)
    }
}

extension RenderPipeline {
    /// Temperature and tint that make `color` (linear RGB, as in the unedited photo) neutral grey.
    public func neutralizingWhiteBalance(for color: SIMD3<Double>, context: CIContext = RenderContext.analysis) -> (temperature: Double, tint: Double) {
        let floats: [Float] = [Float(color.x), Float(color.y), Float(color.z), 1]
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let pixel = CIImage(bitmapData: data, bytesPerRow: 16, size: CGSize(width: 1, height: 1), format: .RGBAf, colorSpace: nil)

        func residual(_ temperature: Double, _ tint: Double) -> SIMD2<Double> {
            var settings = ColorSettings()
            settings.temperature = temperature
            settings.tint = tint
            let output = applyWhiteBalance(settings, to: pixel)
            let read = RenderContext.readFloats(output.cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)), context: context)
            guard read.pixels.count >= 3 else { return .zero }
            let lab = ColorMath.linearSRGBToOklab(Double(read.pixels[0]), Double(read.pixels[1]), Double(read.pixels[2]))
            return SIMD2(lab.1, lab.2)
        }

        // Gauss–Newton on (temperature, tint) with finite-difference derivatives.
        var t = 0.0, u = 0.0
        for _ in 0..<10 {
            let r = residual(t, u)
            if abs(r.x) < 0.0005 && abs(r.y) < 0.0005 { break }
            let h = 2.0
            let rt = residual(t + h, u), ru = residual(t, u + h)
            let jt: SIMD2<Double> = (rt - r) / h
            let ju: SIMD2<Double> = (ru - r) / h
            let det = jt.x * ju.y - ju.x * jt.y
            guard abs(det) > 1e-12 else { break }
            // Solve J * step = -r.
            let stepT = (-r.x * ju.y + ju.x * r.y) / det
            let stepU = (-jt.x * r.y + jt.y * r.x) / det
            t = min(max(t + stepT, -100), 100)
            u = min(max(u + stepU, -100), 100)
        }
        return (t.rounded(), u.rounded())
    }
}
