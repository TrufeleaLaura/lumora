import CoreImage
import Foundation
import LumoraCore
import Vision

/// Finds the sky: smooth, sky-colored areas connected to the top of the photo (plus matching
/// patches seen through trees). The result is guided-filter coefficients (a, b) at medium
/// resolution; the renderer turns them into a full-resolution mask that follows edges.
enum SkyDetector {
    /// Soft sky probability on a small grid (rows top-down), or nil when there's no sky.
    static func probability(_ image: CIImage, person: CIImage?, context: CIContext) -> (values: [Float], width: Int, height: Int)? {
        let small = ImageSource.scaled(image, maxDimension: 320)
        let data = RenderContext.readFloats(small, context: context)
        let w = data.width, h = data.height
        guard w > 8, h > 8 else { return nil }
        let count = w * h

        var personValues = [Float](repeating: 0, count: count)
        if let person {
            let extent = person.extent
            let scaled = person
                .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
                .transformed(by: CGAffineTransform(scaleX: CGFloat(w) / max(extent.width, 1), y: CGFloat(h) / max(extent.height, 1)))
                .cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
            let read = RenderContext.readFloats(scaled, context: context)
            if read.pixels.count == count * 4 {
                for i in 0..<count { personValues[i] = read.pixels[i * 4] }
            }
        }

        var lightness = [Float](repeating: 0, count: count)
        var aValues = [Float](repeating: 0, count: count)
        var bValues = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let r = Double(max(data.pixels[i * 4], 0))
            let g = Double(max(data.pixels[i * 4 + 1], 0))
            let b = Double(max(data.pixels[i * 4 + 2], 0))
            let lab = ColorMath.linearSRGBToOklab(r, g, b)
            lightness[i] = Float(lab.0)
            aValues[i] = Float(lab.1)
            bValues[i] = Float(lab.2)
        }

        // Local texture: standard deviation of lightness in a 5×5 window (integral images).
        var sum = [Double](repeating: 0, count: (w + 1) * (h + 1))
        var sumSquares = [Double](repeating: 0, count: (w + 1) * (h + 1))
        for y in 0..<h {
            var rowSum = 0.0, rowSquares = 0.0
            for x in 0..<w {
                let v = Double(lightness[y * w + x])
                rowSum += v
                rowSquares += v * v
                sum[(y + 1) * (w + 1) + x + 1] = sum[y * (w + 1) + x + 1] + rowSum
                sumSquares[(y + 1) * (w + 1) + x + 1] = sumSquares[y * (w + 1) + x + 1] + rowSquares
            }
        }
        func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
            let t = min(max((x - a) / (b - a), 0), 1)
            return t * t * (3 - 2 * t)
        }

        var probability = [Float](repeating: 0, count: count)
        let radius = 2
        for y in 0..<h {
            let y0 = max(0, y - radius), y1 = min(h - 1, y + radius)
            for x in 0..<w {
                let x0 = max(0, x - radius), x1 = min(w - 1, x + radius)
                let n = Double((x1 - x0 + 1) * (y1 - y0 + 1))
                let s = sum[(y1 + 1) * (w + 1) + x1 + 1] - sum[y0 * (w + 1) + x1 + 1] - sum[(y1 + 1) * (w + 1) + x0] + sum[y0 * (w + 1) + x0]
                let q = sumSquares[(y1 + 1) * (w + 1) + x1 + 1] - sumSquares[y0 * (w + 1) + x1 + 1] - sumSquares[(y1 + 1) * (w + 1) + x0] + sumSquares[y0 * (w + 1) + x0]
                let mean = s / n
                let deviation = Float(max(q / n - mean * mean, 0).squareRoot())

                let i = y * w + x
                let l = lightness[i], a = aValues[i], b = bValues[i]
                let chroma = (a * a + b * b).squareRoot()
                let blue = smoothstep(-0.008, -0.04, b) * (1 - smoothstep(0.03, 0.08, a)) * smoothstep(0.3, 0.45, l)
                let overcast = 0.8 * smoothstep(0.62, 0.78, l) * (1 - smoothstep(0.035, 0.07, chroma))
                let warm = 0.55 * smoothstep(0.55, 0.72, l) * (1 - smoothstep(0.12, 0.2, chroma))
                let color = max(blue, max(overcast, warm))
                let smooth = 1 - smoothstep(0.012, 0.045, deviation)
                let fromTop = Float(y) / Float(h)
                let position = 1 - 0.7 * smoothstep(0.45, 0.95, fromTop)
                probability[i] = color * smooth * position * (1 - personValues[i])
            }
        }

        // Grow from sky-like pixels along the top edge through gradual color changes.
        var sky = [Float](repeating: 0, count: count)
        var queue: [Int] = []
        let seedRows = max(2, h / 12)
        for y in 0..<seedRows {
            for x in 0..<w where probability[y * w + x] > 0.45 {
                let i = y * w + x
                sky[i] = 1
                queue.append(i)
            }
        }
        var head = 0
        func colorDistance(_ i: Int, _ j: Int) -> Float {
            let dl = lightness[i] - lightness[j], da = aValues[i] - aValues[j], db = bValues[i] - bValues[j]
            return (dl * dl + da * da + db * db).squareRoot()
        }
        while head < queue.count {
            let i = queue[head]
            head += 1
            let x = i % w, y = i / w
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let j = ny * w + nx
                guard sky[j] == 0, probability[j] > 0.2, colorDistance(i, j) < 0.03 else { continue }
                sky[j] = 1
                queue.append(j)
            }
        }
        guard queue.count > count / 200 else { return nil }

        // Bright, smooth areas touching the sky (the sun, white clouds) belong to it even
        // across a sharp edge.
        var brightQueue = queue
        var brightHead = 0
        while brightHead < brightQueue.count {
            let i = brightQueue[brightHead]
            brightHead += 1
            let x = i % w, y = i / w
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let j = ny * w + nx
                guard sky[j] == 0, lightness[j] > 0.82, probability[j] > 0.4 else { continue }
                sky[j] = 1
                brightQueue.append(j)
            }
        }

        // Bright holes fully enclosed by sky (a sun with a hard edge, small clouds) are sky too:
        // flood the non-sky area from the image border; whatever it can't reach is enclosed.
        var outside = [Bool](repeating: false, count: count)
        var border: [Int] = []
        for x in 0..<w {
            for y in [0, h - 1] where sky[y * w + x] == 0 && !outside[y * w + x] {
                outside[y * w + x] = true
                border.append(y * w + x)
            }
        }
        for y in 0..<h {
            for x in [0, w - 1] where sky[y * w + x] == 0 && !outside[y * w + x] {
                outside[y * w + x] = true
                border.append(y * w + x)
            }
        }
        var borderHead = 0
        while borderHead < border.count {
            let i = border[borderHead]
            borderHead += 1
            let x = i % w, y = i / w
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let j = ny * w + nx
                guard sky[j] == 0, !outside[j] else { continue }
                outside[j] = true
                border.append(j)
            }
        }
        for i in 0..<count where sky[i] == 0 && !outside[i] && lightness[i] > 0.6 {
            sky[i] = 1
        }

        // Patches of the same sky seen through branches or between buildings: they must match
        // the sky's color at the same height (skies are vertical gradients).
        var rowSums = [SIMD4<Float>](repeating: .zero, count: h)
        var lowestRow = 0
        for i in queue {
            let y = i / w
            rowSums[y] += SIMD4(lightness[i], aValues[i], bValues[i], 1)
            lowestRow = max(lowestRow, y)
        }
        var rowColor = [SIMD3<Float>?](repeating: nil, count: h)
        for y in 0..<h where rowSums[y].w >= 3 {
            let total = rowSums[y]
            rowColor[y] = SIMD3(total.x, total.y, total.z) / total.w
        }
        func nearestRowColor(_ y: Int) -> SIMD3<Float>? {
            for offset in 0...12 {
                if y - offset >= 0, let color = rowColor[y - offset] { return color }
                if y + offset < h, let color = rowColor[y + offset] { return color }
            }
            return nil
        }
        let rowLimit = min(h - 1, lowestRow + h / 20)
        for y in 0...rowLimit {
            guard let reference = nearestRowColor(y) else { continue }
            for x in 0..<w {
                let i = y * w + x
                guard sky[i] == 0, probability[i] > 0.45 else { continue }
                let dl = lightness[i] - reference.x, da = aValues[i] - reference.y, db = bValues[i] - reference.z
                let distance = (dl * dl + da * da + db * db).squareRoot()
                if distance < 0.04 { sky[i] = 0.85 }
            }
        }
        return (sky, w, h)
    }

    /// How likely the photo shows sky, from Vision's scene classifier (0...1), or nil when the
    /// classifier isn't available. Indoor photos with bright walls score near 0.
    static func skyLikelihood(_ image: CIImage) -> Double? {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(ciImage: ImageSource.scaled(image, maxDimension: 512), options: [:])
        guard (try? handler.perform([request])) != nil, let results = request.results, !results.isEmpty else { return nil }
        let skyWords = ["sky", "cloud", "sunset", "sunrise", "horizon", "outdoor", "beach", "mountain", "landscape", "ocean", "sea", "field"]
        var best: Float = 0
        for observation in results where skyWords.contains(where: { observation.identifier.lowercased().contains($0) }) {
            best = max(best, observation.confidence)
        }
        return Double(best)
    }

    /// Edge-refined coefficients from a sky matte stored in the photo file.
    static func coefficients(fromMatte matte: CIImage, image: CIImage, context: CIContext) -> CIImage? {
        let medium = ImageSource.scaled(image, maxDimension: 768)
        let target = medium.extent
        let mask = ImageAnalysis.stretch(matte, over: target)
        let guide = Kernels.perceptualLuma.apply(medium)
        let coefficients = GuidedFilter.coefficients(guide: guide, target: mask, radius: max(2, max(target.width, target.height) * 0.004), eps: 0.001)
        let materialized = RenderContext.materialize(coefficients, context: context, format: .RGBAf)
        let extent = image.extent
        return materialized
            .transformed(by: CGAffineTransform(scaleX: extent.width / target.width, y: extent.height / target.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    /// Guided coefficients (a, b) over the image's extent for the sky mask, or nil.
    static func coefficients(_ image: CIImage, person: CIImage?, context: CIContext) -> CIImage? {
        // Indoors (bright walls, ceilings) there is no sky to find.
        if let likelihood = skyLikelihood(image), likelihood < 0.08 { return nil }
        guard let grid = probability(image, person: person, context: context) else { return nil }
        var floats = [Float](repeating: 1, count: grid.width * grid.height * 4)
        for i in 0..<(grid.width * grid.height) {
            floats[i * 4] = grid.values[i]
            floats[i * 4 + 1] = grid.values[i]
            floats[i * 4 + 2] = grid.values[i]
        }
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let small = CIImage(bitmapData: data, bytesPerRow: grid.width * 16, size: CGSize(width: grid.width, height: grid.height), format: .RGBAf, colorSpace: nil)

        let medium = ImageSource.scaled(image, maxDimension: 768)
        let target = medium.extent
        let mask = small.clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: target.width / CGFloat(grid.width), y: target.height / CGFloat(grid.height)))
            .cropped(to: target)
        let guide = Kernels.perceptualLuma.apply(medium)
        let longSide = max(target.width, target.height)
        let coefficients = GuidedFilter.coefficients(guide: guide, target: mask, radius: max(2, longSide * 0.008), eps: 0.002)
        let materialized = RenderContext.materialize(coefficients, context: context, format: .RGBAf)
        // Stretch over the analyzed image's extent.
        let extent = image.extent
        return materialized
            .transformed(by: CGAffineTransform(scaleX: extent.width / target.width, y: extent.height / target.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }
}
