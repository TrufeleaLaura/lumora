import Foundation

/// Turns face-shape sliders into a warp: landmark moves (MLS) plus local scalings.
/// Works in isotropic units (x across the image width, y scaled by the aspect ratio) so
/// circles stay circles on non-square photos.
public enum FaceReshape {
    /// Frame of a face derived from its landmarks (isotropic units).
    public struct Frame {
        public var eyeMid: SIMD2<Double>
        public var mouth: SIMD2<Double>
        /// Unit vector pointing up the face (mouth → eyes), handles head roll.
        public var up: SIMD2<Double>
        /// Unit vector pointing to the photo's right across the face.
        public var right: SIMD2<Double>
        public var faceWidth: Double
        public var eyeToMouth: Double

        public func side(_ p: SIMD2<Double>) -> Double { FaceReshape.dot(p - eyeMid, right) }
        public func height(_ p: SIMD2<Double>) -> Double { FaceReshape.dot(p - eyeMid, up) }
    }

    static func dot(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x * b.x + a.y * b.y }

    static func normalized(_ v: SIMD2<Double>) -> SIMD2<Double> {
        let length = (v.x * v.x + v.y * v.y).squareRoot()
        return length > 1e-12 ? v / length : SIMD2(0, 1)
    }

    public static func iso(_ p: SIMD2<Double>, aspect: Double) -> SIMD2<Double> { SIMD2(p.x, p.y * aspect) }

    public static func frame(_ face: FaceLandmarks, aspect: Double) -> Frame? {
        guard !face.leftEye.isEmpty, !face.rightEye.isEmpty, !face.outerLips.isEmpty else { return nil }
        let left = iso(face.leftPupil ?? FaceLandmarks.centroid(face.leftEye), aspect: aspect)
        let right = iso(face.rightPupil ?? FaceLandmarks.centroid(face.rightEye), aspect: aspect)
        let eyeMid = (left + right) / 2
        let mouth = iso(FaceLandmarks.centroid(face.outerLips), aspect: aspect)
        let up = normalized(eyeMid - mouth)
        let rightAxis = SIMD2(up.y, -up.x)
        let contour = face.contour.map { iso($0, aspect: aspect) }
        let sides = contour.map { dot($0 - eyeMid, rightAxis) }
        let width = (sides.max() ?? 0) - (sides.min() ?? 0)
        let faceWidth = width > 1e-6 ? width : face.bounds.width
        let between: SIMD2<Double> = eyeMid - mouth
        let distance: Double = (between.x * between.x + between.y * between.y).squareRoot()
        let eyeToMouth: Double = max(distance, 1e-6)
        return Frame(eyeMid: eyeMid, mouth: mouth, up: up, right: rightAxis, faceWidth: faceWidth, eyeToMouth: eyeToMouth)
    }

    /// The warp for one face, or nil if no shape slider is used.
    public static func field(for face: FaceLandmarks, settings s: FaceRetouchSettings, aspect: Double, resolution: Int = 72) -> DisplacementField? {
        guard s.hasReshape, let f = frame(face, aspect: aspect) else { return nil }
        var controls: [WarpControl] = []
        var scales: [LocalScale] = []
        let iso: (SIMD2<Double>) -> SIMD2<Double> = { FaceReshape.iso($0, aspect: aspect) }

        // Face contour: slim, jaw, cheekbones, chin, length.
        let fw = f.faceWidth
        let em = f.eyeToMouth
        for point in face.contour.map(iso) {
            let side: Double = f.side(point)
            let height: Double = f.height(point)
            let sign: Double = side < 0 ? -1 : 1
            let absSide: Double = abs(side)
            let lateral: Double = min(1, absSide / (0.45 * fw))

            // Slimming fades in below the temples and tapers off at the chin, so the outline
            // moves as one smooth curve (no dents).
            let slimWeight: Double = smoothstep(0.15 * em, -0.3 * em, height) * min(1, absSide / (0.22 * fw))
            let slimAmount: Double = s.faceSlim / 100 * 0.055 * fw * slimWeight * (0.6 + 0.4 * lateral)
            let jawWeight: Double = smoothstep(-0.5 * em, -1.1 * em, height)
            let jawLateral: Double = min(1, absSide / (0.3 * fw))
            let jawAmount: Double = s.jaw / 100 * 0.05 * fw * jawWeight * jawLateral
            let cheekShape: Double = (height + 0.25 * em) / (0.55 * em)
            let cheekWeight: Double = exp(-cheekShape * cheekShape)
            let cheekAmount: Double = s.cheekbones / 100 * 0.05 * fw * cheekWeight
            let chinShape: Double = side / (0.2 * fw)
            let chinWeight: Double = exp(-chinShape * chinShape) * smoothstep(0, 1, (-height - em) / (0.5 * em))
            let chinAmount: Double = s.chin / 100 * 0.12 * em * chinWeight
            let lengthWeight: Double = min(max(-height / (2 * em), 0), 1)
            let lengthAmount: Double = s.faceLength / 100 * 0.09 * em * lengthWeight

            let sideways: Double = sign * (cheekAmount - slimAmount - jawAmount)
            let vertical: Double = -(chinAmount + lengthAmount)
            let target: SIMD2<Double> = point + f.right * sideways + f.up * vertical
            controls.append(WarpControl(source: point, target: target))
        }

        // Forehead: synthetic points above the brows.
        let browPoints = (face.leftBrow + face.rightBrow).map(iso)
        let browMid = browPoints.isEmpty ? f.eyeMid + f.up * 0.35 * f.eyeToMouth : FaceLandmarks.centroid(browPoints)
        let foreheadLift: Double = s.forehead / 100 * 0.14 * f.eyeToMouth
        for t in [-0.42, -0.2, 0.0, 0.2, 0.42] {
            let across: Double = t * f.faceWidth
            let above: Double = 0.6 * f.eyeToMouth * (1 - 0.7 * t * t)
            let point: SIMD2<Double> = browMid + f.right * across + f.up * above
            controls.append(WarpControl(source: point, target: point + f.up * foreheadLift))
        }

        // Eyes: distance moves eyes (and half the brows) sideways.
        let eyeShift = s.eyeDistance / 100 * 0.035 * f.faceWidth
        for point in face.leftEye.map(iso) {
            controls.append(WarpControl(source: point, target: point - f.right * eyeShift))
        }
        for point in face.rightEye.map(iso) {
            controls.append(WarpControl(source: point, target: point + f.right * eyeShift))
        }
        // Brows: half the eye shift, plus lift, arch (peak about 2/3 out) and tilt (outer end).
        for brow in [face.leftBrow, face.rightBrow] {
            let points = brow.map(iso)
            let sides: [Double] = points.map(f.side)
            guard let innerSide = sides.min(by: { abs($0) < abs($1) }), let outerSide = sides.max(by: { abs($0) < abs($1) }) else { continue }
            let span: Double = max(abs(outerSide - innerSide), 1e-6)
            for (point, side) in zip(points, sides) {
                let sign: Double = side < 0 ? -1 : 1
                let along: Double = min(max(abs(side - innerSide) / span, 0), 1)
                let archShape: Double = (along - 0.65) / 0.3
                let arch: Double = exp(-archShape * archShape)
                let lift: Double = s.makeup.browLift / 100 * 0.06 * f.eyeToMouth
                let archLift: Double = s.makeup.browArch / 100 * 0.05 * f.eyeToMouth * arch
                let tiltLift: Double = s.makeup.browTilt / 100 * 0.06 * f.eyeToMouth * (along - 0.5)
                let sideways: Double = sign * eyeShift * 0.5
                let target: SIMD2<Double> = point + f.right * sideways + f.up * (lift + archLift + tiltLift)
                controls.append(WarpControl(source: point, target: target))
            }
        }

        // Nose: length and tip move the lowest nose point; the rest of the nose anchors it.
        let nose = face.nose.map(iso)
        if !nose.isEmpty {
            let tipIndex = nose.indices.min { f.height(nose[$0]) < f.height(nose[$1]) } ?? 0
            for (index, point) in nose.enumerated() {
                if index == tipIndex {
                    let lengthMove: Double = -s.noseLength / 100 * 0.08 * f.eyeToMouth
                    let tipMove: Double = s.noseTip / 100 * 0.04 * f.eyeToMouth
                    controls.append(WarpControl(source: point, target: point + f.up * (lengthMove + tipMove)))
                } else {
                    controls.append(.anchor(point))
                }
            }
            if s.noseWidth != 0 {
                let center = FaceLandmarks.centroid(nose)
                let noseSides: [Double] = nose.map(f.side)
                let noseHeights: [Double] = nose.map(f.height)
                let width: Double = (noseSides.max() ?? 0) - (noseSides.min() ?? 0)
                let height: Double = (noseHeights.max() ?? 0) - (noseHeights.min() ?? 0)
                let radiusX: Double = max(width, 0.05 * f.faceWidth) * 0.95
                let radiusY: Double = max(height, 0.1 * f.faceWidth) * 0.75
                let widthScale: Double = 1 + s.noseWidth / 100 * 0.25
                scales.append(LocalScale(center: center, radius: SIMD2(radiusX, radiusY), axis: f.right, scale: SIMD2(widthScale, 1)))
            }
        }

        // Lips: smile lifts the corners; fullness and width scale the mouth.
        let lips = face.outerLips.map(iso)
        if !lips.isEmpty {
            let sides = lips.map(f.side)
            let leftCorner = sides.indices.min { sides[$0] < sides[$1] } ?? 0
            let rightCorner = sides.indices.max { sides[$0] < sides[$1] } ?? 0
            let mouthWidth = (sides.max() ?? 0) - (sides.min() ?? 0)
            for (index, point) in lips.enumerated() {
                if index == leftCorner || index == rightCorner {
                    let sign: Double = index == leftCorner ? -1 : 1
                    let lift: Double = s.smile / 100 * 0.07 * mouthWidth
                    let outward: Double = sign * lift * 0.3
                    let target: SIMD2<Double> = point + f.up * lift + f.right * outward
                    controls.append(WarpControl(source: point, target: target))
                } else {
                    controls.append(.anchor(point))
                }
            }
            let heights = lips.map(f.height)
            let mouthHeight = (heights.max() ?? 0) - (heights.min() ?? 0)
            if s.lipsFullness != 0 || s.lipsWidth != 0 {
                let radiusX: Double = mouthWidth * 0.75
                let radiusY: Double = max(mouthHeight, 0.04 * f.faceWidth) * 1.4
                let scaleX: Double = 1 + s.lipsWidth / 100 * 0.2 + s.lipsFullness / 100 * 0.05
                let scaleY: Double = 1 + s.lipsFullness / 100 * 0.3
                scales.append(LocalScale(center: FaceLandmarks.centroid(lips), radius: SIMD2(radiusX, radiusY), axis: f.right, scale: SIMD2(scaleX, scaleY)))
            }
        }

        // Eyes: size scales each eye around its center.
        if s.eyeSize != 0 {
            for eye in [face.leftEye, face.rightEye] where !eye.isEmpty {
                let points = eye.map(iso)
                let sides: [Double] = points.map(f.side)
                let width: Double = (sides.max() ?? 0) - (sides.min() ?? 0)
                let factor: Double = 1 + s.eyeSize / 100 * 0.22
                // Scales are evaluated in source space (after the backward MLS map), so the
                // original eye center is the right center even when eye distance changes.
                scales.append(LocalScale(
                    center: FaceLandmarks.centroid(points),
                    radius: SIMD2(width * 1.15, width * 0.9),
                    axis: f.right,
                    scale: SIMD2(factor, factor)
                ))
            }
        }

        let region = face.bounds.expanded(by: 2.1)
        return DisplacementField.build(controls: controls, scales: scales, region: region, aspect: aspect, columns: resolution, rows: resolution)
    }

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
