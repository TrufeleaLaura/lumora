import CoreGraphics
import CoreImage
import Foundation
import LumoraCore

/// Soft masks for makeup, eyebrows and hair, rasterized from landmarks.
struct MakeupMaskSet {
    /// (blush, contour, highlight) — heavily feathered. Same region as the retouch masks.
    let c: CIImage
    /// (eyeshadow, brow distance field, 0) — medium feather.
    let d: CIImage
    /// (eyeliner, lashes, brow core) — light feather.
    let e: CIImage
    /// Head area where hair can be recolored (larger region), in .r.
    let head: CIImage
    let headRegion: CGRectValue
}

enum MakeupMasks {
    static func render(face: FaceLandmarks, region: CGRectValue, imageSize: CGSize, context: CIContext, maxSize: CGFloat = 512) -> MakeupMaskSet? {
        let aspect = Double(imageSize.height / max(imageSize.width, 1))
        guard let frame = FaceReshape.frame(face, aspect: aspect) else { return nil }

        let regionWidthPx = CGFloat(region.width) * imageSize.width
        let regionHeightPx = CGFloat(region.height) * imageSize.height
        let scale = min(1, maxSize / max(regionWidthPx, regionHeightPx, 1))
        let width = max(8, Int((regionWidthPx * scale).rounded()))
        let height = max(8, Int((regionHeightPx * scale).rounded()))
        // Mask pixels per isotropic unit (same in x and y).
        let k = CGFloat(width) / CGFloat(region.width)
        let fw = frame.faceWidth
        let em = frame.eyeToMouth

        func iso(_ p: SIMD2<Double>) -> SIMD2<Double> { FaceReshape.iso(p, aspect: aspect) }
        // Isotropic point -> mask pixel.
        func px(_ p: SIMD2<Double>) -> CGPoint {
            let nx: Double = p.x
            let ny: Double = p.y / aspect
            return CGPoint(
                x: CGFloat((nx - region.x) / region.width) * CGFloat(width),
                y: CGFloat((ny - region.y) / region.height) * CGFloat(height)
            )
        }
        func length(_ isoLength: Double) -> CGFloat { CGFloat(isoLength) * k }
        func move(_ p: SIMD2<Double>, right r: Double, up u: Double) -> SIMD2<Double> {
            let sideways: SIMD2<Double> = frame.right * r
            let upward: SIMD2<Double> = frame.up * u
            return p + sideways + upward
        }
        let rollAngle = CGFloat(atan2(frame.right.y, frame.right.x))
        let gray = CGColorSpaceCreateDeviceGray()
        let gradient = CGGradient(colorSpace: gray, colorComponents: [1, 1, 0, 1], locations: [0, 1], count: 2)!

        func softSpot(_ ctx: CGContext, center: SIMD2<Double>, radius: Double, squash: CGFloat = 1, strength: CGFloat = 1) {
            let c = px(center)
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: rollAngle)
            ctx.scaleBy(x: 1, y: squash)
            ctx.setAlpha(strength)
            ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: length(radius), options: [])
            ctx.restoreGState()
        }
        func stroke(_ ctx: CGContext, _ points: [SIMD2<Double>], width lineWidth: Double, gray value: CGFloat = 1) {
            guard let first = points.first else { return }
            ctx.setStrokeColor(gray: value, alpha: 1)
            ctx.setLineWidth(length(lineWidth))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: px(first))
            for point in points.dropFirst() { ctx.addLine(to: px(point)) }
            ctx.strokePath()
        }

        let eyes = [face.leftEye.map(iso), face.rightEye.map(iso)]
        let brows = [face.leftBrow.map(iso), face.rightBrow.map(iso)]
        let contour = face.contour.map(iso)
        let lips = face.outerLips.map(iso)

        // Upper lid contour of an eye, ordered from inner to outer corner.
        func upperLid(_ eye: [SIMD2<Double>]) -> [SIMD2<Double>] {
            guard !eye.isEmpty else { return [] }
            let center = FaceLandmarks.centroid(eye)
            let centerHeight = frame.height(center)
            let upper = eye.filter { frame.height($0) >= centerHeight - 1e-9 }
            let sign: Double = frame.side(center) < 0 ? -1 : 1
            return upper.sorted { sign * frame.side($0) < sign * frame.side($1) }
        }

        // Blush, contour, highlight.
        let blush = FaceMasks.rasterize(width: width, height: height) { ctx in
            for eye in eyes where !eye.isEmpty {
                let center = FaceLandmarks.centroid(eye)
                let sign: Double = frame.side(center) < 0 ? -1 : 1
                softSpot(ctx, center: move(center, right: sign * 0.11 * fw, up: -0.62 * em), radius: 0.17 * fw, squash: 0.72)
            }
        }
        let sculpt = FaceMasks.rasterize(width: width, height: height) { ctx in
            for sign in [-1.0, 1.0] {
                let sideContour = contour.filter { sign * frame.side($0) > 0 }
                if let edge = sideContour.min(by: { abs(frame.height($0) + 0.35 * em) < abs(frame.height($1) + 0.35 * em) }) {
                    let toward: SIMD2<Double> = (frame.mouth - edge) * 0.42
                    stroke(ctx, [edge, edge + toward], width: 0.07 * fw, gray: 0.85)
                }
            }
            let jaw = contour.filter { frame.height($0) < -0.95 * em }.sorted { frame.side($0) < frame.side($1) }
            stroke(ctx, jaw, width: 0.05 * fw, gray: 0.55)
            let crest = face.noseCrest.map(iso)
            for sign in [-1.0, 1.0] where crest.count > 1 {
                stroke(ctx, crest.map { move($0, right: sign * 0.06 * fw, up: 0) }, width: 0.025 * fw, gray: 0.6)
            }
        }
        let glow = FaceMasks.rasterize(width: width, height: height) { ctx in
            for eye in eyes where !eye.isEmpty {
                let center = FaceLandmarks.centroid(eye)
                let sign: Double = frame.side(center) < 0 ? -1 : 1
                softSpot(ctx, center: move(center, right: sign * 0.13 * fw, up: -0.38 * em), radius: 0.08 * fw, squash: 0.6)
            }
            let crest = face.noseCrest.map(iso)
            if crest.count > 1 { stroke(ctx, crest, width: 0.022 * fw, gray: 0.8) }
            if let chin = contour.min(by: { frame.height($0) < frame.height($1) }) {
                softSpot(ctx, center: move(chin, right: 0, up: 0.12 * em), radius: 0.06 * fw)
            }
            if let top = lips.max(by: { frame.height($0) < frame.height($1) }) {
                softSpot(ctx, center: move(top, right: 0, up: 0.04 * em), radius: 0.025 * fw, strength: 0.8)
            }
            let browPoints = brows[0] + brows[1]
            if !browPoints.isEmpty {
                softSpot(ctx, center: move(FaceLandmarks.centroid(browPoints), right: 0, up: 0.35 * em), radius: 0.1 * fw, squash: 0.7, strength: 0.8)
            }
        }

        // Eyeshadow (eyelids), brow distance field, head area.
        let lids = FaceMasks.rasterize(width: width, height: height) { ctx in
            for (eye, brow) in zip(eyes, brows) {
                let lid = upperLid(eye)
                guard lid.count >= 2 else { continue }
                let eyeHeight = frame.height(FaceLandmarks.centroid(eye))
                let browHeight = brow.isEmpty ? eyeHeight + 0.35 * em : frame.height(FaceLandmarks.centroid(brow))
                let gap = max(browHeight - eyeHeight, 0.15 * em)
                let sign: Double = frame.side(FaceLandmarks.centroid(eye)) < 0 ? -1 : 1
                var top: [SIMD2<Double>] = []
                for (index, point) in lid.enumerated() {
                    let t = Double(index) / Double(max(lid.count - 1, 1))
                    top.append(move(point, right: sign * 0.03 * fw * t, up: gap * (0.45 + 0.15 * t)))
                }
                let path = CGMutablePath()
                path.move(to: px(lid[0]))
                for point in lid.dropFirst() { path.addLine(to: px(point)) }
                for point in top.reversed() { path.addLine(to: px(point)) }
                path.closeSubpath()
                ctx.setFillColor(gray: 1, alpha: 1)
                ctx.addPath(path)
                ctx.fillPath()
            }
        }
        // Vision's brow points trace a line along the brow, so brows are drawn as strokes.
        func browLine(_ brow: [SIMD2<Double>]) -> [SIMD2<Double>] {
            brow.sorted { frame.side($0) < frame.side($1) }
        }
        let browField = FaceMasks.rasterize(width: width, height: height) { ctx in
            // Concentric strokes: 1 on the brow line, falling to 0 about 0.035 face widths away.
            let steps = 8
            for step in 0..<steps {
                let widthFactor = Double(steps - step) / Double(steps)
                for brow in brows where brow.count > 1 {
                    stroke(ctx, browLine(brow), width: 0.025 * fw + 0.045 * fw * widthFactor, gray: CGFloat(step + 1) / CGFloat(steps))
                }
            }
        }
        let empty = [UInt8](repeating: 0, count: width * height)

        // Eyeliner, lashes, brow core.
        let liner = FaceMasks.rasterize(width: width, height: height) { ctx in
            for eye in eyes {
                let lid = upperLid(eye)
                guard lid.count >= 2, let outer = lid.last else { continue }
                let sign: Double = frame.side(FaceLandmarks.centroid(eye)) < 0 ? -1 : 1
                stroke(ctx, lid, width: 0.011 * fw)
                stroke(ctx, [outer, move(outer, right: sign * 0.045 * fw, up: 0.022 * fw)], width: 0.008 * fw)
            }
        }
        let lashes = FaceMasks.rasterize(width: width, height: height) { ctx in
            for eye in eyes {
                let lid = upperLid(eye)
                guard lid.count >= 2 else { continue }
                let sign: Double = frame.side(FaceLandmarks.centroid(eye)) < 0 ? -1 : 1
                stroke(ctx, lid, width: 0.016 * fw)
                for index in 0..<(lid.count - 1) {
                    for fraction in [0.25, 0.75] {
                        let base: SIMD2<Double> = lid[index] + (lid[index + 1] - lid[index]) * fraction
                        let t = Double(index) / Double(max(lid.count - 2, 1))
                        let tip = move(base, right: sign * 0.012 * fw * (0.3 + t), up: 0.03 * fw)
                        stroke(ctx, [base, tip], width: 0.0045 * fw)
                    }
                }
            }
        }
        let browCore = FaceMasks.rasterize(width: width, height: height) { ctx in
            for brow in brows where brow.count > 1 {
                stroke(ctx, browLine(brow), width: 0.03 * fw)
            }
        }

        let featherScale = CGFloat(fw) * k
        func soften(_ image: CIImage, _ radius: CGFloat) -> CIImage {
            RenderContext.materialize(GuidedFilter.gaussian(image, radius: max(0.5, radius)), context: context)
        }
        let c = soften(FaceMasks.pack(blush, sculpt, glow, width: width, height: height), featherScale * 0.03)
        let d = soften(FaceMasks.pack(lids, browField, empty, width: width, height: height), featherScale * 0.012)
        let e = soften(FaceMasks.pack(liner, lashes, browCore, width: width, height: height), featherScale * 0.003)

        // Head area for hair color: a tall ellipse around the head, in its own larger region.
        let headRegion = face.bounds.expanded(by: 3.4)
        let headWidthPx = CGFloat(headRegion.width) * imageSize.width
        let headHeightPx = CGFloat(headRegion.height) * imageSize.height
        let headScale = min(1, maxSize / max(headWidthPx, headHeightPx, 1))
        let hw = max(8, Int((headWidthPx * headScale).rounded()))
        let hh = max(8, Int((headHeightPx * headScale).rounded()))
        let hk = CGFloat(hw) / CGFloat(headRegion.width)
        let headCenterIso = move(frame.eyeMid, right: 0, up: 0.25 * em)
        let headCenter = CGPoint(
            x: CGFloat((headCenterIso.x - headRegion.x) / headRegion.width) * CGFloat(hw),
            y: CGFloat((headCenterIso.y / aspect - headRegion.y) / headRegion.height) * CGFloat(hh)
        )
        let headMask = FaceMasks.rasterize(width: hw, height: hh) { ctx in
            ctx.saveGState()
            ctx.translateBy(x: headCenter.x, y: headCenter.y)
            ctx.rotate(by: rollAngle)
            ctx.scaleBy(x: 1, y: 1.45)
            ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: CGFloat(fw) * hk * 0.75, endCenter: .zero, endRadius: CGFloat(fw) * hk * 1.05, options: [.drawsBeforeStartLocation])
            ctx.restoreGState()
        }
        let emptyHead = [UInt8](repeating: 0, count: hw * hh)
        let head = soften(FaceMasks.pack(headMask, emptyHead, emptyHead, width: hw, height: hh), CGFloat(fw) * hk * 0.04)

        return MakeupMaskSet(c: c, d: d, e: e, head: head, headRegion: headRegion)
    }

    /// Average color (OKLab) inside a small rectangle around an isotropic point.
    static func tone(at point: SIMD2<Double>, size: Double, in image: CIImage, aspect: Double, context: CIContext) -> SIMD3<Float>? {
        let extent = image.extent
        let x = point.x - size / 2
        let y = point.y / aspect - size / 2 / aspect
        let rect = CGRect(
            x: extent.minX + CGFloat(x) * extent.width,
            y: extent.minY + CGFloat(y) * extent.height,
            width: CGFloat(size) * extent.width,
            height: CGFloat(size / aspect) * extent.height
        ).intersection(extent)
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        let average = ImageStats.averageColor(of: image.cropped(to: rect), context: context)
        let lab = ColorMath.linearSRGBToOklab(Double(average.x), Double(average.y), Double(average.z))
        return SIMD3(Float(lab.0), Float(lab.1), Float(lab.2))
    }
}
