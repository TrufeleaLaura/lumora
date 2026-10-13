import CoreImage
import Foundation
import LumoraCore

/// Finds small dark or red spots (blemishes, pimples, moles) on a face's skin.
enum BlemishDetector {
    struct Spot: Hashable, Sendable {
        /// Normalized image position (y up).
        var center: SIMD2<Double>
        /// Radius as a fraction of the image width.
        var radius: Double
    }

    static func spots(on face: FaceInfo, image: CIImage, context: CIContext = RenderContext.analysis) -> [Spot] {
        let extent = image.extent
        let region = face.maskRegion
        let rect = CGRect(
            x: extent.minX + CGFloat(region.x) * extent.width,
            y: extent.minY + CGFloat(region.y) * extent.height,
            width: CGFloat(region.width) * extent.width,
            height: CGFloat(region.height) * extent.height
        ).integral.intersection(extent)
        guard rect.width > 16, rect.height > 16 else { return [] }

        // Work at ~384 px across the face region.
        let scale = min(1, 384 / max(rect.width, rect.height))
        let width = max(16, Int(safe: (rect.width * scale).rounded()))
        let height = max(16, Int(safe: (rect.height * scale).rounded()))
        func local(_ input: CIImage) -> CIImage {
            input.cropped(to: rect)
                .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
                .transformed(by: CGAffineTransform(scaleX: CGFloat(width) / rect.width, y: CGFloat(height) / rect.height))
                .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let faceWidthPx = Double(face.landmarks.bounds.width) * Double(extent.width) * Double(scale)
        let lab = local(Kernels.toOklab.apply(image.clampedToExtent().cropped(to: rect)))
        let fine = GuidedFilter.gaussian(lab, radius: CGFloat(max(0.7, faceWidthPx * 0.004)))
        let wide = GuidedFilter.gaussian(lab, radius: CGFloat(max(3, faceWidthPx * 0.03)))
        let skin = local(RenderPipeline.place(face.masksA, region: face.maskRegion, in: extent).composited(over: RenderPipeline.black(extent)))

        let fineRead = RenderContext.readFloats(fine, context: context)
        let wideRead = RenderContext.readFloats(wide, context: context)
        let skinRead = RenderContext.readFloats(skin, context: context)
        let count = width * height
        guard fineRead.pixels.count == count * 4, wideRead.pixels.count == count * 4, skinRead.pixels.count == count * 4 else { return [] }

        // Spot score: darker and/or redder than the surrounding skin, on solid skin only.
        var score = [Float](repeating: 0, count: count)
        for i in 0..<count {
            guard skinRead.pixels[i * 4] > 0.75 else { continue }
            let darker = wideRead.pixels[i * 4] - fineRead.pixels[i * 4]
            let redder = fineRead.pixels[i * 4 + 1] - wideRead.pixels[i * 4 + 1]
            score[i] = darker + 0.9 * max(redder, 0)
        }

        // Local maxima above the threshold, at least a spot apart.
        let spacing = max(2, Int(faceWidthPx * 0.025))
        let threshold: Float = 0.022
        var candidates: [(index: Int, score: Float)] = []
        for y in spacing..<(height - spacing) {
            for x in spacing..<(width - spacing) {
                let i = y * width + x
                let value = score[i]
                guard value > threshold else { continue }
                var isMax = true
                search: for dy in -spacing...spacing {
                    for dx in -spacing...spacing where dx != 0 || dy != 0 {
                        if score[(y + dy) * width + x + dx] > value {
                            isMax = false
                            break search
                        }
                    }
                }
                if isMax { candidates.append((i, value)) }
            }
        }
        candidates.sort { $0.score > $1.score }

        let radius = Double(face.landmarks.bounds.width) * 0.022
        return candidates.prefix(40).map { candidate in
            let x = candidate.index % width, y = candidate.index / width
            // Rows are top-down; the region's origin is its bottom-left corner.
            let px = Double(rect.minX) + (Double(x) + 0.5) / Double(width) * Double(rect.width)
            let py = Double(rect.maxY) - (Double(y) + 0.5) / Double(height) * Double(rect.height)
            return Spot(
                center: SIMD2((px - Double(extent.minX)) / Double(extent.width), (py - Double(extent.minY)) / Double(extent.height)),
                radius: radius
            )
        }
    }
}

extension RenderPipeline {
    /// Heals detected blemishes on each face that asks for it (content-aware fill, cached).
    func applyBlemishes(_ beauty: BeautySettings, to input: CIImage, analysis: ImageAnalysis) -> CIImage {
        var image = input
        for (index, face) in analysis.faces.enumerated() {
            let settings = beauty.settings(for: face.landmarks.anchor)
            guard settings.blemishes > 0 else { continue }
            let spots = analysis.blemishSpots(faceIndex: index)
            guard !spots.isEmpty else { continue }
            var operation = RetouchOperation(tool: .heal)
            operation.strokes = spots.map { BrushStroke(points: [$0.center], radius: $0.radius, feather: 60) }
            // The fill is computed once; the slider only fades it.
            let key = RetouchCache.Key(photo: ObjectIdentifier(analysis), operations: [operation], width: Int(input.extent.width), height: Int(input.extent.height))
            let patch: CIImage?
            if let cached = RetouchCache.shared.patch(key) {
                patch = cached
            } else if let computed = Self.retouchPatch(operation, on: image, analysis: analysis) {
                RetouchCache.shared.store(computed, for: key)
                patch = computed
            } else {
                patch = nil
            }
            if let patch {
                image = TextRenderer.faded(patch, opacity: CGFloat(min(settings.blemishes / 100, 1))).composited(over: image)
            }
        }
        return image
    }
}
