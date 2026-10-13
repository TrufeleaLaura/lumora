import CoreImage
import Foundation
import LumoraCore

extension RenderPipeline {
    private static func linear(_ color: RGBColor) -> CIVector {
        CIVector(x: CGFloat(pow(color.red, 2.2)), y: CGFloat(pow(color.green, 2.2)), z: CGFloat(pow(color.blue, 2.2)), w: 1)
    }

    /// The generated sky for `style` over `extent`, with its horizon at `horizonY` (pixels).
    public func skyImage(_ settings: SkySettings, extent: CGRect, horizonY: CGFloat) -> CIImage {
        let palette = settings.style.palette
        let longSide = max(extent.width, extent.height)
        let hasSun = settings.style == .sunset || settings.style == .golden
        let sun = hasSun ? CGPoint(x: extent.minX + extent.width * 0.68, y: horizonY + extent.height * 0.1) : .zero
        return Kernels.skyLayer.apply(
            extent: extent,
            roiCallback: { _, rect in rect },
            arguments: [
                Self.linear(palette.zenith), Self.linear(palette.horizon), Self.linear(palette.cloudLight), Self.linear(palette.cloudShade),
                CIVector(x: horizonY, y: extent.maxY, z: CGFloat(palette.clouds), w: CGFloat(settings.seed * 3.7 + 11)),
                CIVector(x: longSide * 0.12, y: hasSun ? sun.x : 0, z: sun.y, w: settings.style == .night ? 1 : 0),
            ]
        ) ?? Self.black(extent)
    }

    /// Replaces the sky and relights the landscape to match.
    func applySky(_ sky: SkySettings, to image: CIImage, analysis: ImageAnalysis) -> CIImage {
        guard !sky.isIdentity, let coefficients = analysis.skyCoefficients, let region = analysis.skyRegion else { return image }
        let extent = image.extent
        let mask = Kernels.guidedMask.apply(image, GuidedFilter.upsample(coefficients, to: extent))
        let horizonY = extent.minY + CGFloat(region.y) * extent.height
        let generated = skyImage(sky, extent: extent, horizonY: horizonY)
        // The landscape takes on the sky's color, normalized to keep its brightness.
        let palette = sky.style.palette
        let light = SIMD3(pow(palette.horizon.red, 2.2), pow(palette.horizon.green, 2.2), pow(palette.horizon.blue, 2.2))
        let luma = max(0.2126 * light.x + 0.7152 * light.y + 0.0722 * light.z, 1e-4)
        var tint = light / luma
        if sky.style == .night { tint = SIMD3(0.55, 0.6, 0.85) }
        if sky.style == .dramatic { tint = SIMD3(0.85, 0.88, 0.95) }
        return Kernels.skyBlend.apply(
            image, generated, mask,
            CIVector(x: CGFloat(sky.amount / 100), y: CGFloat(sky.relight / 100), z: 0, w: 0),
            CIVector(x: CGFloat(tint.x), y: CGFloat(tint.y), z: CGFloat(tint.z), w: 1)
        )
    }

    /// Solid color or transparency behind the subject.
    func applyBackground(_ background: BackgroundSettings, to image: CIImage, analysis: ImageAnalysis) -> CIImage {
        guard !background.isIdentity, let subject = analysis.subjectMask else { return image }
        let extent = image.extent
        let mask = Self.stretch(subject, over: extent)
        return Kernels.backgroundReplace.apply(image, mask, Self.linear(background.color), Float(background.mode == .transparent ? 2 : 1))
    }
}
