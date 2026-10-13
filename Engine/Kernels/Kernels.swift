import CoreImage
import Foundation

/// Anchor class used to locate this framework's bundle (and its compiled `default.metallib`).
final class EngineBundleMarker {}

/// Loads the custom Metal Core Image kernels compiled into LumoraEngine.
enum Kernels {
    static let library: Data = {
        let bundle = Bundle(for: EngineBundleMarker.self)
        guard let url = bundle.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else {
            preconditionFailure("LumoraEngine: default.metallib not found in \(bundle.bundlePath)")
        }
        return data
    }()

    /// Loads a color kernel. If one can't be loaded on some device, a pass-through kernel is
    /// used instead (that effect does nothing) rather than crashing the app.
    static func colorKernel(_ name: String) -> CIColorKernel {
        do {
            return try CIColorKernel(functionName: name, fromMetalLibraryData: library)
        } catch {
            NSLog("LumoraEngine: cannot load color kernel %@: %@", name, String(describing: error))
            assertionFailure("cannot load color kernel \(name)")
            return passthroughColor
        }
    }

    static func generalKernel(_ name: String) -> CIKernel {
        do {
            return try CIKernel(functionName: name, fromMetalLibraryData: library)
        } catch {
            NSLog("LumoraEngine: cannot load kernel %@: %@", name, String(describing: error))
            assertionFailure("cannot load kernel \(name)")
            return passthroughGeneral
        }
    }

    private static let passthroughColor: CIColorKernel = {
        // swiftlint:disable:next force_try
        try! CIColorKernel(functionName: "lumora_passthrough", fromMetalLibraryData: library)
    }()

    private static let passthroughGeneral: CIKernel = {
        // swiftlint:disable:next force_try
        try! CIKernel(functionName: "lumora_passthroughSampler", fromMetalLibraryData: library)
    }()

    static func warpKernel(_ name: String) -> CIWarpKernel {
        do {
            return try CIWarpKernel(functionName: name, fromMetalLibraryData: library)
        } catch {
            preconditionFailure("LumoraEngine: cannot load warp kernel \(name): \(error)")
        }
    }

    // Tone
    static let tone = colorKernel("lumora_tone")
    static let localContrast = colorKernel("lumora_localContrast")
    static let dehaze = colorKernel("lumora_dehaze")
    static let darkChannel = colorKernel("lumora_darkChannel")
    static let transmission = colorKernel("lumora_transmission")

    // Guided filter helpers
    static let logLuma = colorKernel("lumora_logLuma")
    static let logLumaPair = colorKernel("lumora_logLumaPair")
    static let perceptualLuma = colorKernel("lumora_perceptualLuma")
    static let perceptualLumaPair = colorKernel("lumora_perceptualLumaPair")
    static let lumaPair = colorKernel("lumora_lumaPair")
    static let guidedSelfCoefficients = colorKernel("lumora_guidedSelfCoefficients")
    static let guidedPack = colorKernel("lumora_guidedPack")
    static let guidedPackSquare = colorKernel("lumora_guidedPackSquare")
    static let guidedCoefficients = colorKernel("lumora_guidedCoefficients")

    // Color
    static let color = colorKernel("lumora_color")
    static let toOklab = colorKernel("lumora_toOklab")
    static let chromaMerge = colorKernel("lumora_chromaMerge")
    static let defringe = colorKernel("lumora_defringe")
    static let curves = generalKernel("lumora_curves")

    // Detail & effects
    static let finish = generalKernel("lumora_finish")
    static let sharpen = colorKernel("lumora_sharpen")
    static let lumaDenoise = colorKernel("lumora_lumaDenoise")
    static let lensVignette = generalKernel("lumora_lensVignette")
    static let lensDistortion = generalKernel("lumora_lensDistortion")
    static let homography = generalKernel("lumora_homography")

    // Face & body
    static let faceRetouch = colorKernel("lumora_faceRetouch")
    static let makeup = colorKernel("lumora_makeup")
    static let hairColor = colorKernel("lumora_hairColor")
    static let bodySkin = colorKernel("lumora_bodySkin")
    static let redEye = colorKernel("lumora_redEye")
    static let displace = generalKernel("lumora_displace")

    // Masks
    static let linearMask = generalKernel("lumora_linearMask")
    static let radialMask = generalKernel("lumora_radialMask")
    static let colorRangeMask = colorKernel("lumora_colorRangeMask")
    static let luminanceMask = colorKernel("lumora_luminanceMask")
    static let maskCombine = colorKernel("lumora_maskCombine")
    static let maskInvert = colorKernel("lumora_maskInvert")
    static let maskMultiply = colorKernel("lumora_maskMultiply")
    static let guidedMask = colorKernel("lumora_guidedMask")
    static let maskBlend = colorKernel("lumora_maskBlend")
    static let maskOverlay = colorKernel("lumora_maskOverlay")
    static let peopleBody = colorKernel("lumora_peopleBody")
    static let peopleFace = colorKernel("lumora_peopleFace")

    // Styles
    static let hdrDrama = colorKernel("lumora_hdrDrama")
    static let tonalContrast = colorKernel("lumora_tonalContrast")
    static let glow = colorKernel("lumora_glow")
    static let brightParts = colorKernel("lumora_brightParts")
    static let halation = colorKernel("lumora_halation")
    static let vintage = colorKernel("lumora_vintage")
    static let noir = colorKernel("lumora_noir")
    static let grunge = colorKernel("lumora_grunge")
    static let grungeTexture = generalKernel("lumora_grungeTexture")
    static let rgbSplit = generalKernel("lumora_rgbSplit")
    static let bandMask = generalKernel("lumora_bandMask")
    static let bokehBoost = colorKernel("lumora_bokehBoost")
    static let weighted = colorKernel("lumora_weighted")
    static let unweight = colorKernel("lumora_unweight")
    static let focusBlend = colorKernel("lumora_focusBlend")

    // Overlays & frames
    static let screenBlend = colorKernel("lumora_screenBlend")
    static let multiplyBlend = colorKernel("lumora_multiplyBlend")
    static let shadowLayer = generalKernel("lumora_shadowLayer")
    static let plasticLayer = generalKernel("lumora_plasticLayer")
    static let prismLayer = generalKernel("lumora_prismLayer")
    static let vhs = generalKernel("lumora_vhs")
    static let roundedMask = generalKernel("lumora_roundedMask")

    // Enhance
    static let skyLayer = generalKernel("lumora_skyLayer")
    static let skyBlend = colorKernel("lumora_skyBlend")
    static let backgroundReplace = colorKernel("lumora_backgroundReplace")
    static let clipping = colorKernel("lumora_clipping")
}

extension CIColorKernel {
    /// Applies the kernel over the first image's extent.
    func apply(_ image: CIImage, _ arguments: Any...) -> CIImage {
        apply(extent: image.extent, arguments: [image as Any] + arguments) ?? image
    }
}

extension CIKernel {
    /// Applies a general kernel whose image inputs are all pixel-aligned with `image`
    /// (each input is read in the destination rect, grown by `margin`).
    func applyAligned(_ image: CIImage, margin: CGFloat = 0, _ arguments: Any...) -> CIImage {
        apply(
            extent: image.extent,
            roiCallback: { _, rect in rect.insetBy(dx: -margin, dy: -margin) },
            arguments: [image as Any] + arguments
        ) ?? image
    }
}
