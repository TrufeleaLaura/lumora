import CoreImage
import Foundation
import LumoraCore

/// One-tap enhancement: measures the photo (brightness percentiles, color cast, haze, noise)
/// and proposes Light, Color, Effects and Detail settings. The result is ordinary edits the
/// user can fine-tune.
public enum AutoEnhance {
    public struct Proposal: Equatable, Sendable {
        public var light = LightSettings()
        public var temperature: Double = 0
        public var tint: Double = 0
        public var vibrance: Double = 0
        public var clarity: Double = 0
        public var dehaze: Double = 0
        public var noiseReduction: Double = 0
        public var colorNoiseReduction: Double = 0

        /// Writes the proposal into a document (keeps everything else).
        public func apply(to document: inout EditDocument, strength: Double = 1) {
            let k = min(max(strength, 0), 1.5)
            document.light.exposure = light.exposure * k
            document.light.contrast = light.contrast * k
            document.light.highlights = light.highlights * k
            document.light.shadows = light.shadows * k
            document.light.whites = light.whites * k
            document.light.blacks = light.blacks * k
            document.color.temperature = temperature * k
            document.color.tint = tint * k
            document.color.vibrance = vibrance * k
            document.effects.clarity = clarity * k
            document.effects.dehaze = dehaze * k
            document.detail.noiseReduction = noiseReduction * min(k, 1)
            document.detail.colorNoiseReduction = colorNoiseReduction * min(k, 1)
        }
    }

    public static func propose(for image: CIImage, context: CIContext = RenderContext.analysis) -> Proposal {
        let small = ImageSource.scaled(image, maxDimension: 256)
        let data = RenderContext.readFloats(small, context: context)
        let count = data.width * data.height
        var proposal = Proposal()
        guard count > 16 else { return proposal }

        var perceptual = [Double](repeating: 0, count: count)
        var neutralA = 0.0, neutralB = 0.0, neutralCount = 0.0
        var chromaSum = 0.0
        var darkChannel = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let r = Double(max(data.pixels[i * 4], 0)), g = Double(max(data.pixels[i * 4 + 1], 0)), b = Double(max(data.pixels[i * 4 + 2], 0))
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let p = pow(y, 1 / 2.2)
            perceptual[i] = p
            let lab = ColorMath.linearSRGBToOklab(r, g, b)
            let chroma = (lab.1 * lab.1 + lab.2 * lab.2).squareRoot()
            chromaSum += chroma
            if p > 0.25, p < 0.9, chroma < 0.09 {
                neutralA += lab.1
                neutralB += lab.2
                neutralCount += 1
            }
            darkChannel[i] = pow(min(r, min(g, b)), 1 / 2.2)
        }
        let sorted = perceptual.sorted()
        func percentile(_ q: Double) -> Double { sorted[min(count - 1, max(0, Int(q * Double(count - 1))))] }

        // Exposure: bring the median toward a pleasant midtone, partially.
        let median = max(percentile(0.5), 0.02)
        let target = 0.47
        var exposure = 0.0
        if median < target - 0.04 || median > target + 0.14 {
            exposure = log2(pow(target, 2.2) / pow(median, 2.2)) * 0.6
            exposure = min(max(exposure, -1.0), 1.5)
        }
        proposal.light.exposure = (exposure * 20).rounded() / 20
        let gain = pow(2, exposure)
        func adjusted(_ p: Double) -> Double { min(pow(pow(p, 2.2) * gain, 1 / 2.2), 1.2) }

        let low = adjusted(percentile(0.01)), high = adjusted(percentile(0.99))
        let p10 = adjusted(percentile(0.1)), p90 = adjusted(percentile(0.9))
        let clipped = Double(perceptual.filter { adjusted($0) > 0.985 }.count) / Double(count)
        let deepShadow = Double(perceptual.filter { adjusted($0) < 0.18 }.count) / Double(count)

        if clipped > 0.02 {
            proposal.light.highlights = -min(60, (clipped * 700).rounded())
        } else if high < 0.92 {
            proposal.light.whites = min(40, ((0.95 - high) * 220).rounded())
        }
        if deepShadow > 0.2 {
            proposal.light.shadows = min(50, (deepShadow * 90).rounded())
        }
        if low > 0.06 {
            proposal.light.blacks = -min(40, ((low - 0.03) * 260).rounded())
        }
        let spread = p90 - p10
        if spread < 0.55 {
            proposal.light.contrast = min(30, ((0.55 - spread) * 90).rounded())
        }

        // White balance from near-neutral midtones (gray world, only with enough evidence).
        if neutralCount > Double(count) * 0.04 {
            let a = neutralA / neutralCount, b = neutralB / neutralCount
            let confidence = min(1, neutralCount / (Double(count) * 0.15))
            proposal.temperature = (min(max(-b * 900, -40), 40) * confidence).rounded()
            proposal.tint = (min(max(-a * 900, -30), 30) * confidence).rounded()
        }

        let meanChroma = chromaSum / Double(count)
        proposal.vibrance = meanChroma < 0.04 ? 25 : (meanChroma < 0.08 ? 15 : 5)
        proposal.clarity = 10
        let haze = darkChannel.sorted()[count / 2]
        if haze > 0.3 {
            proposal.dehaze = min(30, ((haze - 0.3) * 120).rounded())
        }
        let noise = Double(ImageStats.noiseLevel(of: ImageSource.scaled(image, maxDimension: 1024), context: context))
        if noise > 0.012 {
            proposal.noiseReduction = min(50, ((noise - 0.012) * 2500).rounded())
            proposal.colorNoiseReduction = min(60, proposal.noiseReduction + 15)
        }
        return proposal
    }
}
