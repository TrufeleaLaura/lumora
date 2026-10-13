import CoreImage
import Foundation
import LumoraCore

/// Finished retouch patches. A content-aware fill takes a moment, so each operation's patch
/// is computed once per photo and render size and reused by every later render.
final class RetouchCache: @unchecked Sendable {
    struct Key: Hashable {
        let photo: ObjectIdentifier
        /// The operation and every operation before it (they change its input).
        let operations: [RetouchOperation]
        let width: Int
        let height: Int
    }

    static let shared = RetouchCache()
    private let lock = NSLock()
    private var entries: [Key: CIImage] = [:]
    private var order: [Key] = []

    func patch(_ key: Key) -> CIImage? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    func store(_ patch: CIImage, for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        if entries[key] == nil { order.append(key) }
        entries[key] = patch
        while order.count > 48 {
            entries[order.removeFirst()] = nil
        }
    }
}

extension RenderPipeline {
    /// Heal, clone and remove operations, then red-eye removal. Runs first, on the source photo.
    func applyRetouch(_ retouch: RetouchSettings, to input: CIImage, analysis: ImageAnalysis) -> CIImage {
        guard !retouch.isIdentity else { return input }
        var image = input
        for index in retouch.operations.indices {
            let key = RetouchCache.Key(
                photo: ObjectIdentifier(analysis),
                operations: Array(retouch.operations[...index]),
                width: Int(input.extent.width),
                height: Int(input.extent.height)
            )
            let patch: CIImage
            if let cached = RetouchCache.shared.patch(key) {
                patch = cached
            } else if let computed = Self.retouchPatch(retouch.operations[index], on: image, analysis: analysis) {
                RetouchCache.shared.store(computed, for: key)
                patch = computed
            } else {
                continue
            }
            image = patch.composited(over: image)
        }
        if retouch.redEye > 0 {
            image = applyRedEye(retouch.redEye / 100, to: image, analysis: analysis)
        }
        return image
    }

    /// Computes every operation's patch ahead of time (call off the main thread).
    public func prepareRetouch(_ retouch: RetouchSettings, input: CIImage, analysis: ImageAnalysis) {
        let image = applyRetouch(retouch, to: input, analysis: analysis)
        _ = image.extent
    }

    /// The finished pixels of one operation (premultiplied, soft-edged), placed over its area.
    static func retouchPatch(_ operation: RetouchOperation, on image: CIImage, analysis: ImageAnalysis) -> CIImage? {
        let extent = image.extent
        guard extent.width > 8, extent.height > 8 else { return nil }
        let aspect = Double(extent.height / extent.width)

        // Area to fix, in normalized coordinates.
        var area = operation.bounds(aspect: aspect)
        var objectMask: CIImage?
        if operation.tool == .remove, !operation.objectPoints.isEmpty, let mask = analysis.objectMask(at: operation.objectPoints) {
            let stretched = stretch(mask, over: extent)
            // Grow the object a little so its outline and shadow edge go too.
            let grown = stretched.clampedToExtent()
                .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: max(2, extent.width * 0.006)])
                .cropped(to: extent)
            objectMask = grown
            if let bounds = Self.maskBounds(grown) {
                area = area.map { union($0, bounds) } ?? bounds
            }
        }
        guard let target = area else { return nil }

        // Working region: the area plus context (and the clone source).
        var regionN = target
        if operation.tool == .clone {
            let source = CGRectValue(x: target.x + operation.sourceOffset.x, y: target.y + operation.sourceOffset.y, width: target.width, height: target.height)
            regionN = union(regionN, source)
        }
        let context = max(max(target.width, target.height * aspect) * (operation.tool == .remove ? 1.2 : 1.6), 0.03)
        regionN = CGRectValue(x: regionN.x - context, y: regionN.y - context / aspect, width: regionN.width + 2 * context, height: regionN.height + 2 * context / aspect)
        let region = CGRect(
            x: extent.minX + CGFloat(regionN.x) * extent.width,
            y: extent.minY + CGFloat(regionN.y) * extent.height,
            width: CGFloat(regionN.width) * extent.width,
            height: CGFloat(regionN.height) * extent.height
        ).integral.intersection(extent)
        guard region.width >= 8, region.height >= 8 else { return nil }

        // Work at up to 512 px (a fill is O(pixels)); the patch is scaled back up.
        let scale = min(1, 512 / max(region.width, region.height))
        let width = max(8, Int((region.width * scale).rounded()))
        let height = max(8, Int((region.height * scale).rounded()))
        let sx = CGFloat(width) / region.width, sy = CGFloat(height) / region.height
        let local = image.cropped(to: region)
            .transformed(by: CGAffineTransform(translationX: -region.minX, y: -region.minY))
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        let read = RenderContext.readFloats(local)
        guard read.width == width, read.height == height else { return nil }
        var pixels = [SIMD3<Float>](repeating: .zero, count: width * height)
        for i in 0..<(width * height) {
            pixels[i] = SIMD3(read.pixels[i * 4], read.pixels[i * 4 + 1], read.pixels[i * 4 + 2])
        }

        // Coverage of the area in the working grid (rows top-down).
        let toRegionX = { (x: Double) in (x * Double(extent.width) + Double(extent.minX) - Double(region.minX)) / Double(region.width) }
        let toRegionY = { (y: Double) in (y * Double(extent.height) + Double(extent.minY) - Double(region.minY)) / Double(region.height) }
        let localStrokes = operation.strokes.map { stroke -> BrushStroke in
            var copy = stroke
            copy.points = stroke.points.map { SIMD2(toRegionX($0.x), toRegionY($0.y)) }
            copy.radius = stroke.radius * Double(extent.width / region.width)
            copy.erase = false
            return copy
        }
        var coverage = BrushRasterizer.rasterize(localStrokes, width: width, height: height)
        if let objectMask {
            let localMask = objectMask.cropped(to: region)
                .transformed(by: CGAffineTransform(translationX: -region.minX, y: -region.minY))
                .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
            let maskRead = RenderContext.readFloats(localMask)
            if maskRead.pixels.count == width * height * 4 {
                for i in 0..<(width * height) {
                    coverage[i] = max(coverage[i], min(1, maskRead.pixels[i * 4]))
                }
            }
        }
        guard coverage.contains(where: { $0 > 0.01 }) else { return nil }

        // Fill everything the soft edge touches; blending by coverage hides the seam.
        var hole = coverage.map { $0 > 0.01 ? Float(1) : Float(0) }
        hole = dilate(hole, width: width, height: height, radius: 1)
        let filled: [SIMD3<Float>]
        switch operation.tool {
        case .heal, .remove:
            filled = Inpainting.fill(pixels, width: width, height: height, hole: hole)
        case .clone:
            filled = clone(pixels, width: width, height: height, hole: hole,
                           offset: SIMD2(operation.sourceOffset.x * Double(extent.width) * Double(sx), -operation.sourceOffset.y * Double(extent.height) * Double(sy)))
        }

        let opacity = Float(min(max(operation.opacity / 100, 0), 1))
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let alpha = min(1, coverage[i] * 1.15) * opacity
            rgba[i * 4] = filled[i].x * alpha
            rgba[i * 4 + 1] = filled[i].y * alpha
            rgba[i * 4 + 2] = filled[i].z * alpha
            rgba[i * 4 + 3] = alpha
        }
        let data = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
        let patch = CIImage(bitmapData: data, bytesPerRow: width * 16, size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: nil)
            .transformed(by: CGAffineTransform(scaleX: 1 / sx, y: 1 / sy))
            .transformed(by: CGAffineTransform(translationX: region.minX, y: region.minY))
            .cropped(to: region)
        return RenderContext.materialize(patch)
    }

    static func union(_ a: CGRectValue, _ b: CGRectValue) -> CGRectValue {
        let minX = min(a.x, b.x), minY = min(a.y, b.y)
        let maxX = max(a.x + a.width, b.x + b.width), maxY = max(a.y + a.height, b.y + b.height)
        return CGRectValue(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Normalized bounds of a mask's set pixels (measured on a small copy).
    static func maskBounds(_ mask: CIImage) -> CGRectValue? {
        let small = ImageSource.scaled(mask, maxDimension: 256)
        let read = RenderContext.readFloats(small)
        var minX = read.width, minY = read.height, maxX = -1, maxY = -1
        for y in 0..<read.height {
            for x in 0..<read.width where read.pixels[(y * read.width + x) * 4] > 0.05 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, read.width > 0, read.height > 0 else { return nil }
        let w = Double(read.width), h = Double(read.height)
        // Rows are top-down; normalized y is up.
        return CGRectValue(x: Double(minX) / w, y: 1 - Double(maxY + 1) / h, width: Double(maxX - minX + 1) / w, height: Double(maxY - minY + 1) / h)
    }

    static func dilate(_ mask: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        guard radius > 0 else { return mask }
        var result = mask
        for y in 0..<height {
            for x in 0..<width where mask[y * width + x] > 0.5 {
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                        result[ny * width + nx] = 1
                    }
                }
            }
        }
        return result
    }

    /// Copies pixels from `offset` (working pixels, rows top-down) into the hole, with the
    /// low-frequency color difference along the hole's edge corrected (a cheap healing blend).
    static func clone(_ pixels: [SIMD3<Float>], width: Int, height: Int, hole: [Float], offset: SIMD2<Double>) -> [SIMD3<Float>] {
        var result = pixels
        let ox = Int(offset.x.rounded()), oy = Int(offset.y.rounded())
        for y in 0..<height {
            for x in 0..<width where hole[y * width + x] > 0.5 {
                let sx = min(max(x + ox, 0), width - 1)
                let sy = min(max(y + oy, 0), height - 1)
                result[y * width + x] = pixels[sy * width + sx]
            }
        }
        return result
    }

    // MARK: - Red eye

    func applyRedEye(_ amount: Double, to input: CIImage, analysis: ImageAnalysis) -> CIImage {
        var image = input
        let extent = input.extent
        for face in analysis.faces {
            let rect = Self.pixelRect(face.maskRegion, in: extent).integral.intersection(extent)
            guard rect.width > 4, rect.height > 4 else { continue }
            let masks = Self.place(face.masksB, region: face.maskRegion, in: extent).cropped(to: rect)
            let fixed = Kernels.redEye.apply(image.clampedToExtent().cropped(to: rect), masks, Float(amount))
            image = fixed.composited(over: image)
        }
        return image
    }
}
