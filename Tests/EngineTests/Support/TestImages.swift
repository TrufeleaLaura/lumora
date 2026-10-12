import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

/// Synthetic test images, so render tests don't depend on downloaded photos.
enum TestImages {
    /// Patch colors in sRGB: saturated hues, two skin tones and mid grey.
    static let patchColors: [(Double, Double, Double)] = [
        (0.80, 0.15, 0.15),
        (0.90, 0.60, 0.15),
        (0.85, 0.80, 0.20),
        (0.20, 0.65, 0.25),
        (0.15, 0.45, 0.80),
        (0.55, 0.25, 0.70),
        (0.87, 0.68, 0.57), // light skin
        (0.55, 0.38, 0.28), // deep skin
        (0.50, 0.50, 0.50), // mid grey
    ]

    /// Built from Core Image generators. Top half: color patches. Bottom half: black → white ramp.
    static func colorChart(size: CGSize = CGSize(width: 720, height: 480)) -> CIImage {
        let half = size.height / 2

        let ramp = CIFilter.linearGradient()
        ramp.point0 = CGPoint(x: 0, y: 0)
        ramp.point1 = CGPoint(x: size.width, y: 0)
        ramp.color0 = CIColor(red: 0, green: 0, blue: 0)
        ramp.color1 = CIColor(red: 1, green: 1, blue: 1)
        var image = ramp.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: size.width, height: half))

        let width = size.width / CGFloat(patchColors.count)
        for (index, color) in patchColors.enumerated() {
            let rect = CGRect(x: CGFloat(index) * width, y: half, width: width, height: half)
            let ciColor = CIColor(red: CGFloat(color.0), green: CGFloat(color.1), blue: CGFloat(color.2))
            image = CIImage(color: ciColor).cropped(to: rect).composited(over: image)
        }
        return image
    }

    /// The same layout, written as an sRGB PNG file and decoded like a real photo.
    /// The ramp is perceptual (sRGB-encoded values 0 → 1).
    static func fileDecodedChart(width: Int = 720, height: Int = 480) -> CIImage? {
        guard let data = chartPNG(width: width, height: height) else { return nil }
        return CIImage(data: data)
    }

    static func chartPNG(width: Int, height: Int) -> Data? {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let patchWidth = width / patchColors.count
        for row in 0..<height {
            for x in 0..<width {
                let index = (row * width + x) * 4
                if row < height / 2 {
                    // Top rows in memory = top of the image = patches.
                    let color = patchColors[min(x / max(patchWidth, 1), patchColors.count - 1)]
                    pixels[index] = UInt8((color.0 * 255).rounded())
                    pixels[index + 1] = UInt8((color.1 * 255).rounded())
                    pixels[index + 2] = UInt8((color.2 * 255).rounded())
                } else {
                    let value = UInt8((Double(x) / Double(width - 1) * 255).rounded())
                    pixels[index] = value
                    pixels[index + 1] = value
                    pixels[index + 2] = value
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
