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

    static func colorKernel(_ name: String) -> CIColorKernel {
        do {
            return try CIColorKernel(functionName: name, fromMetalLibraryData: library)
        } catch {
            preconditionFailure("LumoraEngine: cannot load color kernel \(name): \(error)")
        }
    }

    static func generalKernel(_ name: String) -> CIKernel {
        do {
            return try CIKernel(functionName: name, fromMetalLibraryData: library)
        } catch {
            preconditionFailure("LumoraEngine: cannot load kernel \(name): \(error)")
        }
    }

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
    static let displace = generalKernel("lumora_displace")
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
