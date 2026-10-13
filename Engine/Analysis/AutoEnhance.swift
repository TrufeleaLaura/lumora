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
            if p > 0.25, p < 0.9, chroma < 0.05 {
                neutralA += lab.1
                neutralB += lab.2
                neutralCount += 1
            }
            darkChannel[i] = pow(min(r, min(g, b)), 1 / 2.2)
        }
        let sorted = perceptual.sorted()
        func percentile(_ q: Double) -> Double { sorted[min(count - 1, max(0, Int(q * Double(count - 1))))] }

        // Exposure: driven by the highlights (a dull photo's brightest areas sit too low),
        // limited so midtones don't wash out; very dark or very bright photos also use the median.
        let median = max(percentile(0.5), 0.02)
        let p98 = max(percentile(0.98), 0.02)
        let p02 = percentile(0.02)
        let evHigh = 2.2 * log2(0.9 / p98)
        let evMid = 2.2 * log2(0.5 / median)
        var exposure = 0.0
        if p98 < 0.82 {
            exposure = min(evHigh, evMid + 0.5) * 0.8
        } else if median < 0.36 {
            exposure = min(evMid * 0.6, max(evHigh, 0))
        } else if median > 0.72, p02 > 0.25 {
            exposure = evMid * 0.5
        }
        exposure = min(max(exposure, -1.0), 1.5)
        proposal.light.exposure = (exposure * 20).rounded() / 20
        let gain = pow(2, proposal.light.exposure)
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

        // White balance from near-neutral midtones. Only warm (yellow/orange) casts and
        // green/magenta tints are corrected: bluish greys are usually sky or shade.
        if neutralCount > Double(count) * 0.04 {
            let a = neutralA / neutralCount, b = neutralB / neutralCount
            let confidence = min(1, neutralCount / (Double(count) * 0.15))
            if b > 0.005 {
                proposal.temperature = (-min((b - 0.005) * 1400, 40) * confidence).rounded()
            }
            if abs(a) > 0.008 {
                let excess = a > 0 ? a - 0.008 : a + 0.008
                proposal.tint = (min(max(-excess * 1200, -30), 30) * confidence).rounded()
            }
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
