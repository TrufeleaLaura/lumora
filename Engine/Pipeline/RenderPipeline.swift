import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import LumoraCore

/// Turns a source image + `EditDocument` into the edited image (a lazy Core Image graph).
/// The same pipeline renders the interactive preview proxy and the full-resolution export.
public struct RenderPipeline {
    public init() {}

    public func apply(_ document: EditDocument, to input: CIImage) -> CIImage {
        guard !document.isIdentity else { return input }
        var image = input
        image = applyWhiteBalance(document.color, to: image)
        image = applyBasicTone(document, to: image)
        image = applyVibrance(document.color, to: image)
        return image
    }

    // MARK: - Stages

    func applyWhiteBalance(_ color: ColorSettings, to image: CIImage) -> CIImage {
        guard color.temperature != 0 || color.tint != 0 else { return image }
        // Telling Core Image the scene light was bluer (higher K) than D65 warms the image.
        let neutralKelvin = 6500 * pow(2.0, color.temperature / 100 * 0.9)
        let filter = CIFilter.temperatureAndTint()
        filter.inputImage = image
        filter.neutral = CIVector(x: CGFloat(neutralKelvin), y: CGFloat(color.tint))
        filter.targetNeutral = CIVector(x: 6500, y: 0)
        return filter.outputImage ?? image
    }

    func applyBasicTone(_ document: EditDocument, to image: CIImage) -> CIImage {
        let light = document.light
        let saturation = document.color.saturation
        guard light.exposure != 0 || light.contrast != 0 || light.whites != 0 || light.blacks != 0 || saturation != 0 else {
            return image
        }
        let arguments: [Any] = [
            image,
            Float(light.exposure),
            Float(light.contrast / 100),
            Float(light.whites / 100),
            Float(light.blacks / 100),
            Float(saturation / 100),
        ]
        return Kernels.basicTone.apply(extent: image.extent, arguments: arguments) ?? image
    }

    func applyVibrance(_ color: ColorSettings, to image: CIImage) -> CIImage {
        guard color.vibrance != 0 else { return image }
        let filter = CIFilter.vibrance()
        filter.inputImage = image
        filter.amount = Float(color.vibrance / 100)
        return filter.outputImage ?? image
    }
}
