import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import LumoraCore

/// Particle layers (dust, hairs, scratches) drawn once with Core Graphics and reused.
enum ParticleLayers {
    private static let lock = NSLock()
    private static var cache: [String: CIImage] = [:]

    private struct Random {
        var state: UInt64
        mutating func next() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state % 1_000_000) / 1_000_000
        }
    }

    /// Premultiplied RGBA layer over (0, 0, width, height).
    static func layer(_ kind: String, style: Int, width: Int, height: Int) -> CIImage {
        let key = "\(kind)-\(style)-\(width)x\(height)"
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let image = draw(kind, style: style, width: width, height: height)
        lock.lock()
        if cache.count > 12 { cache.removeAll() }
        cache[key] = image
        lock.unlock()
        return image
    }

    private static func draw(_ kind: String, style: Int, width: Int, height: Int) -> CIImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let scale = Double(max(width, height)) / 1600
        var random = Random(state: UInt64(0x2545F4914F6CDD1D) &+ UInt64(style + 1) &* 0x9E3779B97F4A7C15 &+ UInt64(kind.count))
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.setShouldAntialias(true)
            context.setLineCap(.round)
            let w = Double(width), h = Double(height)
            if kind == "dust" {
                // Specks: mostly light, some dark.
                for _ in 0..<260 {
                    let x = random.next() * w, y = random.next() * h
                    let r = (0.4 + pow(random.next(), 3) * 2.4) * scale
                    let light = random.next() < 0.7
                    let alpha = 0.35 + random.next() * 0.6
                    context.setFillColor(gray: light ? 1 : 0.05, alpha: alpha)
                    context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                }
                // A few hairs.
                for _ in 0..<7 {
                    let x = random.next() * w, y = random.next() * h
                    let length = (40 + random.next() * 120) * scale
                    let angle = random.next() * .pi * 2
                    let bend = (random.next() - 0.5) * length
                    context.setStrokeColor(gray: random.next() < 0.6 ? 0.95 : 0.08, alpha: 0.5 + random.next() * 0.4)
                    context.setLineWidth(CGFloat((0.6 + random.next() * 0.8) * scale))
                    context.beginPath()
                    context.move(to: CGPoint(x: x, y: y))
                    let end = CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length)
                    let control = CGPoint(x: x + cos(angle) * length * 0.5 - sin(angle) * bend, y: y + sin(angle) * length * 0.5 + cos(angle) * bend)
                    context.addQuadCurve(to: end, control: control)
                    context.strokePath()
                }
            } else {
                // Scratches: long, thin, mostly vertical lines.
                for _ in 0..<18 {
                    let x = random.next() * w
                    let y0 = random.next() * h * 0.6
                    let length = (0.3 + random.next() * 0.7) * h
                    let slant = (random.next() - 0.5) * 0.04 * length
                    context.setStrokeColor(gray: random.next() < 0.75 ? 1 : 0.1, alpha: 0.25 + random.next() * 0.45)
                    context.setLineWidth(CGFloat((0.5 + random.next() * 1.2) * scale))
                    context.beginPath()
                    context.move(to: CGPoint(x: x, y: y0))
                    context.addLine(to: CGPoint(x: x + slant, y: min(h, y0 + length)))
                    context.strokePath()
                }
            }
        }
        let data = Data(bytes)
        return CIImage(bitmapData: data, bytesPerRow: width * 4, size: CGSize(width: width, height: height), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
}

extension RenderPipeline {
    /// Texture overlays on the cropped photo.
    func applyOverlays(_ o: OverlaySettings, to input: CIImage) -> CIImage {
        guard !o.isIdentity else { return input }
        var image = input
        let extent = input.extent
        let longSide = max(extent.width, extent.height)

        if o.paper > 0 {
            let texture = Kernels.grungeTexture.apply(
                extent: extent,
                roiCallback: { _, rect in rect },
                arguments: [CIVector(x: 42, y: longSide * 0.06, z: max(1, longSide * 0.0009), w: 0)]
            ) ?? Self.white(extent)
            // Cream paper with fibers: 1 = no change.
            let paper = texture.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.45, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0.45, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0.45, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0.72, y: 0.67, z: 0.55, w: 0),
            ]).cropped(to: extent)
            image = Kernels.multiplyBlend.apply(image, paper, Float(o.paper / 100))
        }
        if o.shadows > 0 {
            let style = Int(o.shadowStyle.rounded())
            let kinds: [(style: Float, angle: CGFloat)] = [(0, 0.55), (1, 0), (2, 0.08), (3, 0.3), (4, 0.3), (0, .pi / 2)]
            let kind = kinds[min(max(style, 0), kinds.count - 1)]
            let layer = Kernels.shadowLayer.apply(
                extent: extent,
                roiCallback: { _, rect in rect },
                arguments: [CIVector(x: CGFloat(kind.style), y: kind.angle, z: longSide * 0.045, w: longSide * 0.006), CIVector(x: extent.width, y: extent.height)]
            ) ?? Self.white(extent)
            let softness = style >= 3 ? longSide * 0.01 : longSide * 0.004
            image = Kernels.multiplyBlend.apply(image, GuidedFilter.gaussian(layer, radius: softness), Float(o.shadows / 100))
        }
        if o.lightLeak > 0 {
            image = Kernels.screenBlend.apply(image, lightLeak(style: Int(o.lightLeakStyle.rounded()), extent: extent), Float(o.lightLeak / 100))
        }
        if o.plastic > 0 {
            let layer = Kernels.plasticLayer.apply(
                extent: extent,
                roiCallback: { _, rect in rect },
                arguments: [CIVector(x: 3.7, y: longSide * 0.07, z: 0, w: 0)]
            ) ?? Self.black(extent)
            image = Kernels.screenBlend.apply(image, GuidedFilter.gaussian(layer, radius: longSide * 0.002), Float(o.plastic / 100 * 0.7))
        }
        if o.prism > 0 {
            let style = CGFloat(o.prismStyle.rounded())
            // A faint shifted ghost near one edge, plus a rainbow band.
            let ghost = input.transformed(by: CGAffineTransform(translationX: longSide * 0.025, y: longSide * 0.004))
                .composited(over: input).cropped(to: extent)
            let edge = CIFilter.smoothLinearGradient()
            edge.point0 = CGPoint(x: extent.minX, y: extent.midY)
            edge.point1 = CGPoint(x: extent.minX + extent.width * 0.45, y: extent.midY)
            edge.color0 = CIColor(red: 1, green: 1, blue: 1)
            edge.color1 = CIColor(red: 0, green: 0, blue: 0)
            let ghostLayer = Kernels.maskMultiply.apply(Kernels.perceptualLuma.apply(ghost), edge.outputImage!.cropped(to: extent))
            image = Kernels.screenBlend.apply(image, ghostLayer, Float(o.prism / 100 * 0.35))
            let band = Kernels.prismLayer.apply(
                extent: extent,
                roiCallback: { _, rect in rect },
                arguments: [CIVector(
                    x: extent.minX + extent.width * (0.18 + 0.12 * style),
                    y: extent.minY + extent.height * 0.5,
                    z: 1.1 + 0.3 * style,
                    w: longSide * 0.06
                )]
            ) ?? Self.black(extent)
            image = Kernels.screenBlend.apply(image, band, Float(o.prism / 100 * 0.8))
        }
        if o.dust > 0 || o.scratches > 0 {
            let factor = min(1, 1600 / longSide)
            let width = max(8, Int(safe: (extent.width * factor).rounded()))
            let height = max(8, Int(safe: (extent.height * factor).rounded()))
            for (kind, amount) in [("dust", o.dust), ("scratches", o.scratches)] where amount > 0 {
                let layer = ParticleLayers.layer(kind, style: Int(o.dustStyle.rounded()), width: width, height: height)
                let placed = Self.stretch(layer, over: extent)
                image = TextRenderer.faded(placed, opacity: CGFloat(amount / 100)).composited(over: image).cropped(to: extent)
            }
        }
        return image
    }

    /// Warm light leaks: soft colored blobs from the edges (six variations).
    private func lightLeak(style: Int, extent: CGRect) -> CIImage {
        typealias Blob = (x: CGFloat, y: CGFloat, radius: CGFloat, color: (CGFloat, CGFloat, CGFloat))
        let styles: [[Blob]] = [
            [(0.0, 1.0, 0.55, (1.0, 0.45, 0.1)), (-0.05, 0.6, 0.35, (0.9, 0.15, 0.1))],
            [(1.05, 0.5, 0.5, (0.95, 0.15, 0.35)), (1.0, 0.9, 0.3, (1.0, 0.5, 0.2))],
            [(0.5, 1.1, 0.5, (1.0, 0.75, 0.25)), (0.15, 1.0, 0.3, (1.0, 0.4, 0.1))],
            [(0.5, -0.1, 0.55, (1.0, 0.6, 0.45)), (0.9, 0.0, 0.3, (1.0, 0.3, 0.2))],
            [(-0.05, 0.3, 0.4, (0.95, 0.2, 0.15)), (0.5, 1.05, 0.35, (1.0, 0.8, 0.3)), (1.05, 0.5, 0.35, (0.3, 0.45, 1.0))],
            [(0.0, 0.0, 0.45, (1.0, 0.35, 0.1)), (0.35, 0.3, 0.25, (1.0, 0.6, 0.2))],
        ]
        let blobs = styles[min(max(style, 0), styles.count - 1)]
        let longSide = max(extent.width, extent.height)
        var layer = Self.black(extent)
        for blob in blobs {
            let gradient = CIFilter.radialGradient()
            gradient.center = CGPoint(x: extent.minX + blob.x * extent.width, y: extent.minY + blob.y * extent.height)
            gradient.radius0 = 0
            gradient.radius1 = Float(blob.radius * longSide)
            gradient.color0 = CIColor(red: blob.color.0, green: blob.color.1, blue: blob.color.2)
            gradient.color1 = CIColor(red: 0, green: 0, blue: 0)
            if let output = gradient.outputImage?.cropped(to: extent) {
                layer = output.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: layer]).cropped(to: extent)
            }
        }
        return layer
    }
}
