import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A procedurally drawn landscape with the situations photo tools must handle:
/// a bright sky with a sun (highlights), hazy distant mountains (dehaze), textured hills
/// and ground (clarity/texture), a deep shadow area with faint detail (shadows),
/// sensor-like noise (noise reduction) and a strip of color patches (color tools).
/// Generated on the CPU as an sRGB PNG and decoded like a real photo.
enum TestScene {
    static let width = 960
    static let height = 640

    // Regions (in Core Image coordinates, y up) used by numeric tests.
    static let skyRect = CGRect(x: 60, y: 560, width: 200, height: 50)
    static let sunRect = CGRect(x: 700, y: 500, width: 40, height: 40)
    static let mountainRect = CGRect(x: 400, y: 230, width: 80, height: 40)
    static let groundRect = CGRect(x: 300, y: 120, width: 200, height: 60)
    static let shadowRect = CGRect(x: 40, y: 110, width: 120, height: 60)
    static let patchY: CGFloat = 20

    static func patchRect(_ index: Int) -> CGRect {
        let patchWidth = CGFloat(width) / CGFloat(TestImages.patchColors.count)
        return CGRect(x: CGFloat(index) * patchWidth + 20, y: patchY + 10, width: patchWidth - 40, height: 30)
    }

    static func image() -> CIImage {
        CIImage(data: png())!
    }

    static func png() -> Data {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let w = Double(width), h = Double(height)

        func hash(_ x: Int, _ y: Int, _ seed: Int) -> Double {
            var v = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 1_442_695_041)
            v = (v ^ (v >> 13)) &* 1_274_126_177
            v = v ^ (v >> 16)
            return Double(v & 0xFFFFFF) / Double(0xFFFFFF)
        }
        func smoothNoise(_ x: Double, _ y: Double, _ scale: Double, _ seed: Int) -> Double {
            let fx = x / scale, fy = y / scale
            let ix = Int(floor(fx)), iy = Int(floor(fy))
            let tx = fx - floor(fx), ty = fy - floor(fy)
            let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
            let a = hash(ix, iy, seed), b = hash(ix + 1, iy, seed)
            let c = hash(ix, iy + 1, seed), d = hash(ix + 1, iy + 1, seed)
            return (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy
        }
        func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> (Double, Double, Double) {
            (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
        }

        for row in 0..<height {
            // y measured upward like Core Image.
            let y = h - 1 - Double(row)
            for column in 0..<width {
                let x = Double(column)
                var color: (Double, Double, Double)

                let mountainLine = h * 0.50 + 38 * sin(x * 0.011) + 22 * sin(x * 0.029 + 1.3) + 10 * sin(x * 0.07)
                let hillLine = h * 0.36 + 26 * sin(x * 0.008 + 2.0) + 12 * sin(x * 0.023)
                let shadowEdge = x < 230 && y < h * 0.33

                if y > mountainLine {
                    // Sky: deep blue at the top, pale at the horizon, a bright sun with a glow.
                    let t = min(1, (y - mountainLine) / (h - mountainLine))
                    color = mix((0.86, 0.89, 0.93), (0.38, 0.58, 0.90), pow(t, 0.8))
                    let sunDistance = hypot(x - 720, y - 520)
                    let glow = exp(-pow(sunDistance / 70, 2)) * 0.5 + (sunDistance < 26 ? 1 : 0)
                    color = mix(color, (1, 0.97, 0.9), min(1, glow))
                } else if y > hillLine {
                    // Distant mountains veiled by haze.
                    let detail = smoothNoise(x, y, 14, 3) * 0.6 + smoothNoise(x, y, 4, 4) * 0.4
                    let rock = mix((0.30, 0.34, 0.42), (0.48, 0.52, 0.60), detail)
                    color = mix(rock, (0.80, 0.84, 0.90), 0.62)
                } else if y > 60 {
                    // Hills and ground: green/brown texture with fine detail.
                    let detail = smoothNoise(x, y, 22, 5) * 0.5 + smoothNoise(x, y, 6, 6) * 0.3 + hash(column, row, 7) * 0.2
                    color = mix((0.16, 0.30, 0.10), (0.42, 0.50, 0.22), detail)
                    if shadowEdge {
                        // Deep shadow with faint texture.
                        color = (color.0 * 0.12, color.1 * 0.12, color.2 * 0.14)
                    }
                } else {
                    // Color patch strip.
                    let index = min(Int(x / (w / Double(TestImages.patchColors.count))), TestImages.patchColors.count - 1)
                    let c = TestImages.patchColors[index]
                    color = (c.0, c.1, c.2)
                }

                // Sensor-like noise (luminance + a little color noise), stronger in the dark.
                let luminance = 0.3 * color.0 + 0.59 * color.1 + 0.11 * color.2
                let amount = 0.025 + 0.03 * (1 - luminance)
                let n = (hash(column, row, 11) - 0.5) * amount
                let cn = (hash(column / 2, row / 2, 12) - 0.5) * amount * 0.6
                color = (color.0 + n + cn, color.1 + n, color.2 + n - cn)

                let index = (row * width + column) * 4
                pixels[index] = UInt8(max(0, min(255, (color.0 * 255).rounded())))
                pixels[index + 1] = UInt8(max(0, min(255, (color.1 * 255).rounded())))
                pixels[index + 2] = UInt8(max(0, min(255, (color.2 * 255).rounded())))
            }
        }

        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }
}
