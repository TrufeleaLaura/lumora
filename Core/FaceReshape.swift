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
        let eyeToMouth = max(((eyeMid - mouth).x * (eyeMid - mouth).x + (eyeMid - mouth).y * (eyeMid - mouth).y).squareRoot(), 1e-6)
        return Frame(eyeMid: eyeMid, mouth: mouth, up: up, right: rightAxis, faceWidth: faceWidth, eyeToMouth: eyeToMouth)
    }

    /// The warp for one face, or nil if no shape slider is used.
    public static func field(for face: FaceLandmarks, settings s: FaceRetouchSettings, aspect: Double, resolution: Int = 72) -> DisplacementField? {
        guard s.hasReshape, let f = frame(face, aspect: aspect) else { return nil }
        var controls: [WarpControl] = []
        var scales: [LocalScale] = []
        let iso: (SIMD2<Double>) -> SIMD2<Double> = { FaceReshape.iso($0, aspect: aspect) }

        // Face contour: slim, jaw, cheekbones, chin, length.
        for point in face.contour.map(iso) {
            let side = f.side(point)
            let height = f.height(point)
            let sign: Double = side < 0 ? -1 : 1
            let lateral = min(1, abs(side) / (0.45 * f.faceWidth))
            var delta = SIMD2<Double>(0, 0)
            delta -= f.right * sign * (s.faceSlim / 100 * 0.07 * f.faceWidth) * lateral
            let jawWeight = smoothstep(0, 1, (-height - 0.6 * f.eyeToMouth) / (0.9 * f.eyeToMouth))
            delta -= f.right * sign * (s.jaw / 100 * 0.06 * f.faceWidth) * jawWeight * min(1, abs(side) / (0.3 * f.faceWidth))
            let cheekWeight = exp(-pow((height + 0.25 * f.eyeToMouth) / (0.55 * f.eyeToMouth), 2))
            delta += f.right * sign * (s.cheekbones / 100 * 0.05 * f.faceWidth) * cheekWeight
            let chinWeight = exp(-pow(side / (0.2 * f.faceWidth), 2)) * smoothstep(0, 1, (-height - f.eyeToMouth) / (0.5 * f.eyeToMouth))
            delta -= f.up * (s.chin / 100 * 0.12 * f.eyeToMouth) * chinWeight
            delta -= f.up * (s.faceLength / 100 * 0.09 * f.eyeToMouth) * min(max(-height / (2 * f.eyeToMouth), 0), 1)
            controls.append(WarpControl(source: point, target: point + delta))
        }

        // Forehead: synthetic points above the brows.
        let browPoints = (face.leftBrow + face.rightBrow).map(iso)
        let browMid = browPoints.isEmpty ? f.eyeMid + f.up * 0.35 * f.eyeToMouth : FaceLandmarks.centroid(browPoints)
        for t in [-0.42, -0.2, 0.0, 0.2, 0.42] {
            let point = browMid + f.right * t * f.faceWidth + f.up * (0.6 * f.eyeToMouth) * (1 - 0.7 * t * t)
            let lift = s.forehead / 100 * 0.14 * f.eyeToMouth
            controls.append(WarpControl(source: point, target: point + f.up * lift))
        }

        // Eyes: distance moves eyes (and half the brows) sideways.
        let eyeShift = s.eyeDistance / 100 * 0.035 * f.faceWidth
        for point in face.leftEye.map(iso) {
            controls.append(WarpControl(source: point, target: point - f.right * eyeShift))
        }
        for point in face.rightEye.map(iso) {
            controls.append(WarpControl(source: point, target: point + f.right * eyeShift))
        }
        for point in browPoints {
            let sign: Double = f.side(point) < 0 ? -1 : 1
            controls.append(WarpControl(source: point, target: point + f.right * sign * eyeShift * 0.5))
        }

        // Nose: length and tip move the lowest nose point; the rest of the nose anchors it.
        let nose = face.nose.map(iso)
        if !nose.isEmpty {
            let tipIndex = nose.indices.min { f.height(nose[$0]) < f.height(nose[$1]) } ?? 0
            for (index, point) in nose.enumerated() {
                if index == tipIndex {
                    let move = -s.noseLength / 100 * 0.08 * f.eyeToMouth + s.noseTip / 100 * 0.04 * f.eyeToMouth
                    controls.append(WarpControl(source: point, target: point + f.up * move))
                } else {
                    controls.append(.anchor(point))
                }
            }
            if s.noseWidth != 0 {
                let center = FaceLandmarks.centroid(nose)
                let width = (nose.map(f.side).max() ?? 0) - (nose.map(f.side).min() ?? 0)
                let height = (nose.map(f.height).max() ?? 0) - (nose.map(f.height).min() ?? 0)
                scales.append(LocalScale(
                    center: center,
                    radius: SIMD2(max(width, 0.05 * f.faceWidth) * 0.95, max(height, 0.1 * f.faceWidth) * 0.75),
                    axis: f.right,
                    scale: SIMD2(1 + s.noseWidth / 100 * 0.25, 1)
                ))
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
                    let lift = s.smile / 100 * 0.07 * mouthWidth
                    controls.append(WarpControl(source: point, target: point + f.up * lift + f.right * sign * lift * 0.3))
                } else {
                    controls.append(.anchor(point))
                }
            }
            let heights = lips.map(f.height)
            let mouthHeight = (heights.max() ?? 0) - (heights.min() ?? 0)
            if s.lipsFullness != 0 || s.lipsWidth != 0 {
                scales.append(LocalScale(
                    center: FaceLandmarks.centroid(lips),
                    radius: SIMD2(mouthWidth * 0.75, max(mouthHeight, 0.04 * f.faceWidth) * 1.4),
                    axis: f.right,
                    scale: SIMD2(1 + s.lipsWidth / 100 * 0.2 + s.lipsFullness / 100 * 0.05, 1 + s.lipsFullness / 100 * 0.3)
                ))
            }
        }

        // Eyes: size scales each eye around its center.
        if s.eyeSize != 0 {
            for eye in [face.leftEye, face.rightEye] where !eye.isEmpty {
                let points = eye.map(iso)
                let width = (points.map(f.side).max() ?? 0) - (points.map(f.side).min() ?? 0)
                let factor = 1 + s.eyeSize / 100 * 0.22
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
