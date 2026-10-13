import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import LumoraCore

extension RenderPipeline {
    /// Creative effects (after the look): HDR/Drama, tonal contrast, glow, halation, vintage,
    /// noir, grunge, RGB split, then lens blur.
    func applyStyles(_ styles: CreativeSettings, to input: CIImage, reference: CIImage, analysis: ImageAnalysis, scale: CGFloat) -> CIImage {
        guard !styles.isIdentity else { return input }
        var image = input
        let extent = image.extent
        let longSide = max(extent.width, extent.height)

        if styles.hdr > 0 || styles.drama > 0 {
            let toneBase = GuidedFilter.upsample(analysis.toneBase, to: extent)
            let clarityBase = GuidedFilter.upsample(analysis.clarityBase, to: extent)
            let fineLog = GuidedFilter.gaussian(Kernels.logLuma.apply(image), radius: max(1, longSide * 0.0015))
            image = Kernels.hdrDrama.apply(image, toneBase, clarityBase, fineLog, CIVector(
                x: CGFloat(styles.hdr / 100), y: CGFloat(styles.drama / 100), z: CGFloat(styles.dramaSaturation / 100), w: 0
            ))
        }
        if styles.tonalHigh > 0 || styles.tonalMid > 0 || styles.tonalLow > 0 {
            let blurredLog = GuidedFilter.gaussian(Kernels.logLuma.apply(image), radius: max(1, longSide * 0.004))
            image = Kernels.tonalContrast.apply(image, blurredLog, CIVector(
                x: CGFloat(styles.tonalHigh / 100), y: CGFloat(styles.tonalMid / 100), z: CGFloat(styles.tonalLow / 100), w: 0
            ))
        }
        if styles.glow > 0 {
            let blurred = GuidedFilter.gaussian(image, radius: longSide * 0.012)
            image = Kernels.glow.apply(image, blurred, CIVector(x: CGFloat(styles.glow / 100), y: CGFloat(styles.glowWarmth / 100), z: 0, w: 0))
        }
        if styles.halation > 0 {
            let bright = Kernels.brightParts.apply(image, Float(0.55))
            let halo = GuidedFilter.gaussian(bright, radius: longSide * 0.006)
            image = Kernels.halation.apply(image, halo, Float(styles.halation / 100))
        }
        if styles.vintage > 0 {
            image = Kernels.vintage.apply(image, Float(styles.vintage / 100))
        }
        if styles.noir > 0 {
            image = Kernels.noir.apply(image, Float(styles.noir / 100))
        }
        if styles.grunge > 0 {
            image = applyGrunge(styles, to: image)
        }
        if styles.rgbSplit > 0 {
            let offset = CGFloat(styles.rgbSplit / 100) * longSide * 0.006
            image = Kernels.rgbSplit.apply(
                extent: extent,
                roiCallback: { _, rect in rect.insetBy(dx: -offset - 1, dy: -1) },
                arguments: [image.clampedToExtent(), CIVector(x: offset, y: 0)]
            ) ?? image
        }
        if styles.lensBlur.amount > 0 {
            image = applyLensBlur(styles.lensBlur, to: image, analysis: analysis)
        }
        return image
    }

    // MARK: - Grunge

    private func applyGrunge(_ styles: CreativeSettings, to image: CIImage) -> CIImage {
        let extent = image.extent
        let longSide = max(extent.width, extent.height)
        let variant = Int(styles.grungeStyle.rounded())
        // Texture: two noise scales and faint scratches, relative to the image size.
        let random = CIFilter.randomGenerator().outputImage!
            .transformed(by: CGAffineTransform(translationX: CGFloat(variant) * 137, y: CGFloat(variant) * 71))
        func noise(_ sx: CGFloat, _ sy: CGFloat) -> CIImage {
            random.transformed(by: CGAffineTransform(scaleX: max(1, sx), y: max(1, sy)))
                .cropped(to: extent)
                .settingAlphaOne(in: extent)
        }
        let coarse = GuidedFilter.gaussian(noise(longSide * 0.02, longSide * 0.02), radius: longSide * 0.01)
        let fine = noise(longSide * 0.0012, longSide * 0.0012)
        let scratches = noise(longSide * 0.0008, longSide * 0.4)
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 6, kCIInputBrightnessKey: -1.8])
        let texture = coarse
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.7, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0.7, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0.7, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0.15, y: 0.15, z: 0.15, w: 0),
            ])
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: fine.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.3, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0.3, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0.3, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: -0.15, y: -0.15, z: -0.15, w: 0),
            ])])
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: scratches])
            .cropped(to: extent)
        // Each variant has its own color cast (OKLab a, b).
        let casts: [(Double, Double)] = [(0.01, 0.03), (-0.02, 0.02), (0.03, -0.01), (0.0, -0.03), (0.02, 0.05)]
        let cast = casts[min(max(variant, 0), casts.count - 1)]
        return Kernels.grunge.apply(image, texture, CIVector(x: CGFloat(styles.grunge / 100), y: CGFloat(cast.0), z: CGFloat(cast.1), w: 0))
    }

    // MARK: - Lens blur

    /// Where the photo stays sharp (1) for lens blur, over `extent`.
    public func focusMask(_ blur: LensBlurSettings, extent: CGRect, analysis: ImageAnalysis) -> CIImage {
        let transition = 0.05 + blur.transition / 100 * 0.6
        switch blur.mode {
        case .subject:
            if let subject = analysis.subjectMask {
                let mask = Self.stretch(subject, over: extent)
                return GuidedFilter.gaussian(mask, radius: max(extent.width, extent.height) * 0.003 * (1 + transition * 4))
            }
            fallthrough
        case .radial:
            let radius = CGFloat(blur.size) * extent.width
            let center = CGPoint(x: extent.minX + CGFloat(blur.center.x) * extent.width, y: extent.minY + CGFloat(blur.center.y) * extent.height)
            let outer = radius * CGFloat(1 + transition * 2)
            return Kernels.radialMask.apply(
                extent: extent,
                roiCallback: { _, rect in rect },
                arguments: [
                    CIVector(x: center.x, y: center.y, z: outer, w: outer * 0.85),
                    CIVector(x: 1, y: 0, z: CGFloat(1 - radius / outer), w: 0),
                ]
            ) ?? Self.white(extent)
        case .band:
            let radians = blur.angle * .pi / 180
            let normal = CIVector(x: CGFloat(-sin(radians)), y: CGFloat(cos(radians)))
            let center = CIVector(x: extent.minX + CGFloat(blur.center.x) * extent.width, y: extent.minY + CGFloat(blur.center.y) * extent.height)
            let halfWidth = CGFloat(blur.size) * extent.width * 0.5
            let fade = CGFloat(transition) * extent.height * 0.5
            return Kernels.bandMask.apply(
                extent: extent,
                roiCallback: { _, rect in rect },
                arguments: [center, normal, Float(halfWidth), Float(fade)]
            ) ?? Self.white(extent)
        }
    }

    func applyLensBlur(_ blur: LensBlurSettings, to image: CIImage, analysis: ImageAnalysis) -> CIImage {
        let extent = image.extent
        let longSide = max(extent.width, extent.height)
        let radius = CGFloat(blur.amount / 100) * longSide * 0.022
        guard radius >= 0.5 else { return image }
        let focus = focusMask(blur, extent: extent, analysis: analysis)

        // Behind a subject, rebuild the background first so the subject doesn't smear into it.
        var source = image
        if blur.mode == .subject, analysis.subjectMask != nil {
            let background = Kernels.maskInvert.apply(focus)
            let weighted = Kernels.weighted.apply(image, background)
            let spread = GuidedFilter.gaussian(weighted, radius: radius * 0.8)
            source = Kernels.unweight.apply(spread, image, background)
        }
        let boosted = Kernels.bokehBoost.apply(source, Float(blur.bokeh / 100))
        func bokeh(_ r: CGFloat) -> CIImage {
            boosted.clampedToExtent()
                .applyingFilter("CIBokehBlur", parameters: [
                    kCIInputRadiusKey: min(r, 500),
                    "inputRingAmount": 0,
                    "inputRingSize": 0.1,
                    "inputSoftness": 1,
                ])
                .cropped(to: extent)
        }
        let medium = bokeh(radius * 0.45)
        let full = bokeh(radius)
        return Kernels.focusBlend.apply(image, medium, full, focus, CIVector(x: CGFloat(blur.miniature / 100), y: 0, z: 0, w: 0))
    }
}
