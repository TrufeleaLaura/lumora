import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import LumoraCore

/// Caches LUT data in the layout Core Image's color cube filter expects.
enum LUTCache {
    private static let lock = NSLock()
    private static var entries: [String: (size: Int, data: Data)] = [:]

    static func cubeData(for id: String, lut: CubeLUT) -> (size: Int, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        if let cached = entries[id], cached.size == lut.size {
            return cached
        }
        let floats = lut.cubeData()
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        entries[id] = (lut.size, data)
        return (lut.size, data)
    }
}

extension RenderPipeline {
    /// Applies a look (recipe and/or LUT) on top of the image, blended by its strength.
    public func applyLook(_ look: LookSettings, to image: CIImage, analysis: ImageAnalysis) -> CIImage {
        guard look.isActive else { return image }
        var output = image
        if let recipe = look.recipe {
            var document = EditDocument()
            document.light = recipe.light
            document.color = recipe.color
            document.mixer = recipe.mixer
            document.grading = recipe.grading
            document.blackWhite = recipe.blackWhite
            document.curve = recipe.curve
            output = applyWhiteBalance(document.color, to: output)
            output = applyTone(document.light, to: output, analysis: analysis)
            output = applyCurves(document.curve, to: output)
            output = applyColor(document, to: output)
        }
        if let lutID = look.lutID, let lut = lutProvider(lutID) {
            output = applyLUT(lut, id: lutID, to: output)
        }
        let amount = min(max(look.amount / 100, 0), 1)
        if amount < 0.999 {
            let blend = CIFilter.dissolveTransition()
            blend.inputImage = image
            blend.targetImage = output
            blend.time = Float(amount)
            output = blend.outputImage?.cropped(to: image.extent) ?? output
        }
        return output
    }

    /// 3D LUT through Core Image's color cube (the LUT works on sRGB-encoded values).
    func applyLUT(_ lut: CubeLUT, id: String, to image: CIImage) -> CIImage {
        let cube = LUTCache.cubeData(for: id, lut: lut)
        let filter = CIFilter.colorCubeWithColorSpace()
        filter.inputImage = image
        filter.cubeDimension = Float(cube.size)
        filter.cubeData = cube.data
        filter.colorSpace = RenderContext.sRGB
        return filter.outputImage?.cropped(to: image.extent) ?? image
    }

    /// The user's effects plus the active look's grain, fade and vignette (scaled by strength).
    func effectiveEffects(_ document: EditDocument) -> EffectsSettings {
        var effects = document.effects
        guard document.look.isActive, let recipe = document.look.recipe else { return effects }
        let amount = min(max(document.look.amount / 100, 0), 1)
        effects.fade = min(100, effects.fade + recipe.fade * amount)
        effects.grain = min(100, effects.grain + recipe.grain * amount)
        effects.vignette = max(-100, min(100, effects.vignette + recipe.vignette * amount))
        return effects
    }
}
