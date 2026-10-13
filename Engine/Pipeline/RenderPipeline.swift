import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import LumoraCore

/// Turns a source image + `EditDocument` into the edited image (a lazy Core Image graph).
/// The same pipeline renders the interactive preview proxy and the full-resolution export.
///
/// Stage order: heal/clone/remove → face retouch → makeup → body skin → face reshape → body reshape → optics → local contrast → white balance → dehaze → tone → curves → color
/// → masks (local adjustments) → look → creative styles and lens blur
/// → noise reduction → sharpening → geometry (rotate, perspective, crop) → finishing (vignette, fade, grain).
public struct RenderPipeline {
    /// Looks up imported LUTs by id.
    let lutProvider: (String) -> CubeLUT?

    public init(lutProvider: @escaping (String) -> CubeLUT? = { LUTStore.shared.lut(id: $0) }) {
        self.lutProvider = lutProvider
    }

    /// - Parameters:
    ///   - input: the source image (full resolution or a downscaled proxy), origin at (0, 0).
    ///   - scale: `input` width divided by the full-resolution width. Pixel-based radii
    ///     (sharpening, noise reduction) use it so the preview matches the export.
    ///   - analysis: cached per-photo analysis; computed on demand when nil.
    ///   - includeCrop: false while the crop tool is open (shows the whole rotated photo).
    ///   - includeGeometry: false while face/body tools are open (overlays match the source photo).
    public func apply(_ document: EditDocument, to input: CIImage, scale: CGFloat = 1, analysis: ImageAnalysis? = nil, includeCrop: Bool = true, includeGeometry: Bool = true) -> CIImage {
        guard !document.isIdentity else { return input }
        let analysis = analysis ?? ImageAnalysis(image: input)
        var image = input
        image = applyRetouch(document.retouch, to: image, analysis: analysis)
        image = applyBeauty(document.beauty, to: image, analysis: analysis)
        image = applyMakeup(document.beauty, to: image, analysis: analysis)
        image = applyBodySkin(document.body, to: image, analysis: analysis)
        image = applyFaceWarp(document.beauty, to: image, analysis: analysis)
        image = applyBodyWarp(document.body, to: image, analysis: analysis)
        image = applyOptics(document.optics, to: image, scale: scale)
        image = applyLocalContrast(document.effects, to: image, analysis: analysis)
        image = applyWhiteBalance(document.color, to: image)
        image = applyDehaze(document.effects.dehaze, to: image, analysis: analysis)
        image = applyTone(document.light, to: image, analysis: analysis)
        image = applyCurves(document.curve, to: image)
        image = applyColor(document, to: image)
        image = applyMasks(document.masks, to: image, reference: input, analysis: analysis, scale: scale)
        image = applyLook(document.look, to: image, analysis: analysis)
        image = applyStyles(document.styles, to: image, reference: input, analysis: analysis, scale: scale)
        image = applyNoiseReduction(document.detail, to: image, scale: scale)
        image = applySharpening(document.detail, to: image, scale: scale)
        if includeGeometry {
            image = applyGeometry(document.geometry, to: image, includeCrop: includeCrop)
        }
        image = applyFinish(effectiveEffects(document), to: image)
        return image
    }

    // MARK: - Optics

    func applyOptics(_ optics: OpticsSettings, to input: CIImage, scale: CGFloat) -> CIImage {
        var image = input
        let extent = image.extent
        let center = CIVector(x: extent.midX, y: extent.midY)
        let halfDiagonal = hypot(extent.width, extent.height) / 2

        if optics.vignetteCorrection != 0 {
            let frame = CIVector(x: center.x, y: center.y, z: halfDiagonal, w: CGFloat(optics.vignetteCorrection / 100))
            image = Kernels.lensVignette.applyAligned(image, frame)
        }
        if optics.distortion != 0 {
            let k = CGFloat(optics.distortion / 100 * 0.15)
            let frame = CIVector(x: center.x, y: center.y, z: halfDiagonal, w: k)
            let margin = abs(k) * halfDiagonal * 1.2 + 4
            image = Kernels.lensDistortion.apply(
                extent: extent,
                roiCallback: { _, rect in rect.insetBy(dx: -margin, dy: -margin) },
                arguments: [image.clampedToExtent(), frame]
            ) ?? image
        }
        if optics.defringe > 0 {
            let luma = Kernels.perceptualLuma.apply(image)
            let blurred = GuidedFilter.gaussian(luma, radius: max(1, 3 * scale))
            image = Kernels.defringe.apply(image, blurred, Float(optics.defringe / 100))
        }
        return image
    }

    // MARK: - Light

    func applyLocalContrast(_ effects: EffectsSettings, to image: CIImage, analysis: ImageAnalysis) -> CIImage {
        guard effects.texture != 0 || effects.clarity != 0 else { return image }
        let extent = image.extent
        let logLuma = Kernels.logLuma.apply(image)
        let blurredLog = effects.texture != 0
            ? GuidedFilter.gaussian(logLuma, radius: max(1, 0.0012 * max(extent.width, extent.height)))
            : logLuma
        let clarityBase = effects.clarity != 0
            ? GuidedFilter.upsample(analysis.clarityBase, to: extent)
            : GuidedFilter.identity(extent: extent)
        return Kernels.localContrast.apply(image, blurredLog, clarityBase, Float(effects.texture / 100), Float(effects.clarity / 100))
    }

    func applyWhiteBalance(_ color: ColorSettings, to image: CIImage) -> CIImage {
        guard color.temperature != 0 || color.tint != 0 else { return image }
        // Telling Core Image the scene light was bluer (higher K) than D65 warms the image.
        let neutralKelvin = 6500 * pow(2.0, color.temperature / 100 * 0.9)
        let filter = CIFilter.temperatureAndTint()
        filter.inputImage = image
        filter.neutral = CIVector(x: CGFloat(neutralKelvin), y: CGFloat(color.tint))
        filter.targetNeutral = CIVector(x: 6500, y: 0)
        return filter.outputImage?.cropped(to: image.extent) ?? image
    }

    func applyDehaze(_ amount: Double, to image: CIImage, analysis: ImageAnalysis) -> CIImage {
        guard amount != 0 else { return image }
        let haze = analysis.haze
        let coefficients = GuidedFilter.upsample(haze.coefficients, to: image.extent)
        let airlight = CIVector(x: CGFloat(haze.airlight.x), y: CGFloat(haze.airlight.y), z: CGFloat(haze.airlight.z), w: 1)
        return Kernels.dehaze.apply(image, coefficients, airlight, Float(amount / 100))
    }

    func applyTone(_ light: LightSettings, to image: CIImage, analysis: ImageAnalysis) -> CIImage {
        guard light != LightSettings() else { return image }
        let base = (light.highlights != 0 || light.shadows != 0)
            ? GuidedFilter.upsample(analysis.toneBase, to: image.extent)
            : GuidedFilter.identity(extent: image.extent)
        return Kernels.tone.apply(
            image,
            base,
            Float(light.exposure),
            Float(light.contrast / 100),
            Float(light.highlights / 100),
            Float(light.shadows / 100),
            Float(light.whites / 100),
            Float(light.blacks / 100)
        )
    }

    // MARK: - Curves

    func applyCurves(_ curve: ToneCurveSettings, to image: CIImage) -> CIImage {
        guard !ToneCurveMath.isIdentity(curve) else { return image }
        let size = 1024
        let table = ToneCurveMath.lookupTable(curve, count: size)
        var floats = [Float](repeating: 1, count: size * 4)
        for (index, entry) in table.enumerated() {
            floats[index * 4] = Float(entry.0)
            floats[index * 4 + 1] = Float(entry.1)
            floats[index * 4 + 2] = Float(entry.2)
        }
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let lut = CIImage(bitmapData: data, bytesPerRow: size * 16, size: CGSize(width: size, height: 1), format: .RGBAf, colorSpace: nil)
        let lutExtent = lut.extent
        return Kernels.curves.apply(
            extent: image.extent,
            roiCallback: { index, rect in index == 0 ? rect : lutExtent },
            arguments: [image, lut, Float(size)]
        ) ?? image
    }

    // MARK: - Color

    func applyColor(_ document: EditDocument, to image: CIImage) -> CIImage {
        let mixer = document.mixer
        let grading = document.grading
        let bw = document.blackWhite
        let color = document.color
        guard mixer != ColorMixerSettings() || grading != ColorGradingSettings() || bw.isEnabled
            || color.saturation != 0 || color.vibrance != 0 else { return image }

        func band(_ values: [Double], _ start: Int) -> CIVector {
            func value(_ i: Int) -> CGFloat { i < values.count ? CGFloat(values[i] / 100) : 0 }
            return CIVector(x: value(start), y: value(start + 1), z: value(start + 2), w: value(start + 3))
        }
        func wheel(_ wheel: GradingWheel) -> CIVector {
            let direction = ColorMath.oklabDirection(forWheelHue: wheel.hue)
            let strength = wheel.saturation / 100 * 0.08
            return CIVector(x: CGFloat(direction.0 * strength), y: CGFloat(direction.1 * strength), z: CGFloat(wheel.luminance / 100 * 0.12), w: 0)
        }

        let basic = CIVector(x: CGFloat(color.saturation / 100), y: CGFloat(color.vibrance / 100), z: bw.isEnabled ? 1 : 0, w: 0)
        let gradeParams = CIVector(x: CGFloat(grading.balance / 100), y: CGFloat(grading.blending / 100), z: 0, w: 0)
        return Kernels.color.apply(
            image,
            band(mixer.hue, 0), band(mixer.hue, 4),
            band(mixer.saturation, 0), band(mixer.saturation, 4),
            band(mixer.luminance, 0), band(mixer.luminance, 4),
            basic,
            band(bw.mix, 0), band(bw.mix, 4),
            wheel(grading.shadows), wheel(grading.midtones), wheel(grading.highlights), wheel(grading.global),
            gradeParams
        )
    }

    // MARK: - Detail

    func applyNoiseReduction(_ detail: DetailSettings, to input: CIImage, scale: CGFloat) -> CIImage {
        var image = input
        if detail.noiseReduction > 0 {
            let strength = detail.noiseReduction / 100
            let pair = Kernels.perceptualLumaPair.apply(image)
            let radius = max(1, 3 * scale)
            let eps = Float(pow(0.006 + strength * 0.05, 2))
            let coefficients = GuidedFilter.selfCoefficients(pair: pair, radius: radius, eps: eps)
            image = Kernels.lumaDenoise.apply(image, coefficients, Float(strength), Float(detail.noiseDetail / 100))
        }
        if detail.colorNoiseReduction > 0 {
            let strength = detail.colorNoiseReduction / 100
            let lab = Kernels.toOklab.apply(image)
            let radius = max(1, (2 + 6 * strength) * scale)
            let blurred = GuidedFilter.gaussian(lab, radius: radius)
            // Edges are detected at the same scale as the chroma blur, so color can't bleed across them.
            let blurredLuma = GuidedFilter.gaussian(Kernels.perceptualLuma.apply(image), radius: radius)
            image = Kernels.chromaMerge.apply(image, blurred, blurredLuma, Float(min(1, strength * 1.2)))
        }
        return image
    }

    func applySharpening(_ detail: DetailSettings, to image: CIImage, scale: CGFloat) -> CIImage {
        guard detail.sharpening > 0 else { return image }
        let radius = detail.sharpenRadius * scale
        guard radius >= 0.25 else { return image }
        let luma = Kernels.perceptualLuma.apply(image)
        let blurred = GuidedFilter.gaussian(luma, radius: radius)
        let wide = GuidedFilter.gaussian(luma, radius: max(1, radius * 4))
        return Kernels.sharpen.apply(
            image,
            blurred,
            wide,
            Float(detail.sharpening / 100),
            Float(detail.sharpenDetail / 100),
            Float(detail.sharpenMasking / 100)
        )
    }

    // MARK: - Finishing

    func applyFinish(_ effects: EffectsSettings, to image: CIImage) -> CIImage {
        guard effects.vignette != 0 || effects.grain > 0 || effects.fade > 0 else { return image }
        let extent = image.extent
        let longSide = max(extent.width, extent.height)

        var noise = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: extent)
        var grainGain = 1.0
        if effects.grain > 0 {
            // Grain cell size is relative to the image, so preview and export look alike.
            let cell = longSide * CGFloat(0.00035 + effects.grainSize / 100 * 0.0012)
            let roughness = effects.grainRoughness / 100
            let random = CIFilter.randomGenerator().outputImage!
                .transformed(by: CGAffineTransform(scaleX: max(cell, 0.5), y: max(cell, 0.5)))
                .cropped(to: extent)
                .settingAlphaOne(in: extent)
            let blur = Double(cell) * (1 - roughness) * 0.7
            noise = GuidedFilter.gaussian(random, radius: CGFloat(blur))
            grainGain = 1 + 1.5 * (1 - roughness)
        }

        let vignette = CIVector(
            x: CGFloat(effects.vignette / 100),
            y: CGFloat(effects.vignetteMidpoint / 100),
            z: CGFloat(effects.vignetteRoundness / 100),
            w: CGFloat(effects.vignetteFeather / 100)
        )
        let vignetteExtra = CIVector(x: CGFloat(effects.vignetteHighlights / 100), y: 0, z: 0, w: 0)
        let frame = CIVector(x: extent.minX, y: extent.minY, z: extent.width, w: extent.height)
        let grain = CIVector(x: CGFloat(effects.grain / 100 * grainGain), y: 0, z: 0, w: 0)
        return Kernels.finish.applyAligned(image, noise, vignette, vignetteExtra, frame, grain, Float(effects.fade / 100))
    }
}
