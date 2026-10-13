import CoreGraphics
import CoreImage
import Foundation
import LumoraCore
import Vision

/// A detected face with everything the retouch and reshape stages need.
public struct FaceInfo: @unchecked Sendable {
    public let landmarks: FaceLandmarks
    /// Average cheek skin color in OKLab (L, a, b).
    public let skinTone: SIMD3<Float>
    /// Soft feature masks covering `maskRegion` (normalized). Channels:
    /// masksA = (skin, lips, mouth interior), masksB = (eyes, iris, under-eye).
    public let masksA: CIImage
    public let masksB: CIImage
    public let maskRegion: CGRectValue
}

public enum FaceAnalyzer {
    /// Detects faces with Vision's 76-point landmarks. Results are sorted left to right.
    public static func detect(in image: CIImage) -> [FaceLandmarks] {
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return (request.results ?? [])
            .compactMap(convert)
            .sorted { $0.bounds.midX < $1.bounds.midX }
    }

    static func convert(_ observation: VNFaceObservation) -> FaceLandmarks? {
        guard let landmarks = observation.landmarks else { return nil }
        let box = observation.boundingBox
        func points(_ region: VNFaceLandmarkRegion2D?) -> [SIMD2<Double>] {
            guard let region else { return [] }
            return region.normalizedPoints.map {
                SIMD2(Double(box.minX + $0.x * box.width), Double(box.minY + $0.y * box.height))
            }
        }
        // Order features by position in the photo (Vision's left/right is the subject's).
        var eyes = [points(landmarks.leftEye), points(landmarks.rightEye)]
        var brows = [points(landmarks.leftEyebrow), points(landmarks.rightEyebrow)]
        var pupils = [points(landmarks.leftPupil).first, points(landmarks.rightPupil).first]
        if FaceLandmarks.centroid(eyes[0]).x > FaceLandmarks.centroid(eyes[1]).x {
            eyes.swapAt(0, 1)
            brows.swapAt(0, 1)
            pupils.swapAt(0, 1)
        }
        guard !eyes[0].isEmpty, !eyes[1].isEmpty else { return nil }
        return FaceLandmarks(
            bounds: CGRectValue(x: Double(box.minX), y: Double(box.minY), width: Double(box.width), height: Double(box.height)),
            contour: points(landmarks.faceContour),
            leftEye: eyes[0],
            rightEye: eyes[1],
            leftBrow: brows[0],
            rightBrow: brows[1],
            nose: points(landmarks.nose),
            noseCrest: points(landmarks.noseCrest),
            outerLips: points(landmarks.outerLips),
            innerLips: points(landmarks.innerLips),
            leftPupil: pupils[0],
            rightPupil: pupils[1],
            roll: observation.roll?.doubleValue ?? 0
        )
    }

    /// Full analysis of each face: landmarks, skin tone and masks.
    public static func analyze(_ image: CIImage, context: CIContext = RenderContext.analysis) -> [FaceInfo] {
        let extent = image.extent
        return detect(in: image).map { face in
            let tone = skinTone(of: face, in: image, context: context)
            let masks = FaceMasks.render(face: face, imageSize: extent.size, context: context)
            return FaceInfo(landmarks: face, skinTone: tone, masksA: masks.a, masksB: masks.b, maskRegion: masks.region)
        }
    }

    /// Average skin color from two cheek patches (between eye and mouth corner, toward the outside).
    static func skinTone(of face: FaceLandmarks, in image: CIImage, context: CIContext) -> SIMD3<Float> {
        let extent = image.extent
        let aspect = Double(extent.height / max(extent.width, 1))
        guard let frame = FaceReshape.frame(face, aspect: aspect) else { return SIMD3(0.7, 0.03, 0.04) }
        var samples: [SIMD4<Float>] = []
        for eye in [face.leftEye, face.rightEye] {
            let eyeCenter = FaceReshape.iso(FaceLandmarks.centroid(eye), aspect: aspect)
            let sign: Double = frame.side(eyeCenter) < 0 ? -1 : 1
            let cheek = eyeCenter - frame.up * frame.eyeToMouth * 0.55 + frame.right * sign * frame.faceWidth * 0.05
            let size = frame.faceWidth * 0.1
            let rect = CGRect(
                x: CGFloat(cheek.x - size / 2) * extent.width,
                y: CGFloat(cheek.y / aspect - size / 2 / aspect) * extent.height,
                width: CGFloat(size) * extent.width,
                height: CGFloat(size / aspect) * extent.height
            ).intersection(extent)
            guard !rect.isEmpty else { continue }
            samples.append(ImageStats.averageColor(of: image.cropped(to: rect), context: context))
        }
        guard !samples.isEmpty else { return SIMD3(0.7, 0.03, 0.04) }
        let average = samples.reduce(SIMD4<Float>(0, 0, 0, 0), +) / Float(samples.count)
        let lab = ColorMath.linearSRGBToOklab(Double(average.x), Double(average.y), Double(average.z))
        return SIMD3(Float(lab.0), Float(lab.1), Float(lab.2))
    }
}

/// Rasterizes feature masks from landmarks with Core Graphics.
enum FaceMasks {
    static func render(face: FaceLandmarks, imageSize: CGSize, context: CIContext, maxSize: CGFloat = 512) -> (a: CIImage, b: CIImage, region: CGRectValue) {
        let region = face.bounds.expanded(by: 2.1)
        let regionWidthPx = CGFloat(region.width) * imageSize.width
        let regionHeightPx = CGFloat(region.height) * imageSize.height
        let scale = min(1, maxSize / max(regionWidthPx, regionHeightPx, 1))
        let width = max(8, Int((regionWidthPx * scale).rounded()))
        let height = max(8, Int((regionHeightPx * scale).rounded()))

        // Normalized image point -> mask pixel (y up, like Core Graphics).
        func px(_ p: SIMD2<Double>) -> CGPoint {
            CGPoint(
                x: CGFloat((p.x - region.x) / region.width) * CGFloat(width),
                y: CGFloat((p.y - region.y) / region.height) * CGFloat(height)
            )
        }
        func polygon(_ points: [SIMD2<Double>]) -> CGPath {
            let path = CGMutablePath()
            guard let first = points.first else { return path }
            path.move(to: px(first))
            for point in points.dropFirst() { path.addLine(to: px(point)) }
            path.closeSubpath()
            return path
        }
        let faceWidthPx = CGFloat(face.bounds.width / region.width) * CGFloat(width)

        let aspect = Double(imageSize.height / max(imageSize.width, 1))
        let frame = FaceReshape.frame(face, aspect: aspect)

        // Skin: face oval (jaw contour + forehead arc) minus eyes, brows and lips.
        let skin = rasterize(width: width, height: height) { ctx in
            var outline = face.contour
            if let frame {
                let brows = face.leftBrow + face.rightBrow
                let browMid = FaceReshape.iso(brows.isEmpty ? FaceLandmarks.centroid(face.leftEye + face.rightEye) : FaceLandmarks.centroid(brows), aspect: aspect)
                // Forehead arc between the temples (Vision's contour only covers the jaw).
                for t in stride(from: -0.5, through: 0.5, by: 0.1) {
                    let p = browMid + frame.right * t * frame.faceWidth * 0.95 + frame.up * frame.eyeToMouth * (0.75 * (1 - 1.6 * t * t))
                    outline.append(SIMD2(p.x, p.y / aspect))
                }
                // The face is star-shaped around the eyes: order all points by angle.
                outline.sort { a, b in
                    let ca = FaceReshape.iso(a, aspect: aspect) - frame.eyeMid
                    let cb = FaceReshape.iso(b, aspect: aspect) - frame.eyeMid
                    return atan2(ca.y, ca.x) < atan2(cb.y, cb.x)
                }
            }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.addPath(polygon(outline))
            ctx.fillPath()
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.setStrokeColor(gray: 0, alpha: 1)
            ctx.setLineJoin(.round)
            for eye in [face.leftEye, face.rightEye] {
                ctx.addPath(polygon(eye))
                ctx.setLineWidth(faceWidthPx * 0.05)
                ctx.drawPath(using: .fillStroke)
            }
            for brow in [face.leftBrow, face.rightBrow] where !brow.isEmpty {
                ctx.addPath(polygon(brow))
                ctx.setLineWidth(faceWidthPx * 0.045)
                ctx.drawPath(using: .fillStroke)
            }
            ctx.addPath(polygon(face.outerLips))
            ctx.setLineWidth(faceWidthPx * 0.02)
            ctx.drawPath(using: .fillStroke)
        }

        let lips = rasterize(width: width, height: height) { ctx in
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.addPath(polygon(face.outerLips))
            ctx.fillPath()
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.addPath(polygon(face.innerLips))
            ctx.fillPath()
        }

        let mouth = rasterize(width: width, height: height) { ctx in
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.addPath(polygon(face.innerLips))
            ctx.fillPath()
        }

        let eyes = rasterize(width: width, height: height) { ctx in
            ctx.setFillColor(gray: 1, alpha: 1)
            for eye in [face.leftEye, face.rightEye] {
                ctx.addPath(polygon(eye))
                ctx.fillPath()
            }
        }

        let iris = rasterize(width: width, height: height) { ctx in
            for (eye, pupil) in [(face.leftEye, face.leftPupil), (face.rightEye, face.rightPupil)] where !eye.isEmpty {
                let center = px(pupil ?? FaceLandmarks.centroid(eye))
                let points = eye.map(px)
                let eyeHeight = (points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0)
                let eyeWidth = (points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0)
                let radius = max(eyeHeight * 0.62, eyeWidth * 0.2)
                ctx.saveGState()
                ctx.addPath(polygon(eye))
                ctx.clip()
                ctx.setFillColor(gray: 1, alpha: 1)
                ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                ctx.restoreGState()
            }
        }

        let underEye = rasterize(width: width, height: height) { ctx in
            guard let frame else { return }
            ctx.setFillColor(gray: 1, alpha: 1)
            for eye in [face.leftEye, face.rightEye] where !eye.isEmpty {
                let isoPoints = eye.map { FaceReshape.iso($0, aspect: aspect) }
                let center = FaceLandmarks.centroid(isoPoints)
                let lower = isoPoints.filter { frame.height($0) <= frame.height(center) }.sorted { frame.side($0) < frame.side($1) }
                guard lower.count >= 2 else { continue }
                let drop = frame.eyeToMouth * 0.32
                let bottom = lower.reversed().map { $0 - frame.up * drop * (1 - 0.5 * pow(abs(frame.side($0) - frame.side(center)) / max(frame.faceWidth * 0.12, 1e-6), 2)) }
                let outline = (lower + bottom).map { SIMD2($0.x, $0.y / aspect) }
                ctx.addPath(polygon(outline))
                ctx.fillPath()
            }
        }

        let feather = max(1, faceWidthPx * 0.015)
        let a = pack(skin, lips, mouth, width: width, height: height)
        let b = pack(eyes, iris, underEye, width: width, height: height)
        func soften(_ image: CIImage, radius: CGFloat) -> CIImage {
            RenderContext.materialize(GuidedFilter.gaussian(image, radius: radius), context: context)
        }
        return (soften(a, radius: feather), soften(b, radius: feather * 0.6), region)
    }

    /// Draws into an 8-bit grayscale buffer (rows top-down, drawing coordinates y-up).
    static func rasterize(width: Int, height: Int, draw: (CGContext) -> Void) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height)
        bytes.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            ctx.setShouldAntialias(true)
            draw(ctx)
        }
        return bytes
    }

    /// Interleaves three grayscale masks into an RGBA image (alpha = 1), no color management.
    static func pack(_ r: [UInt8], _ g: [UInt8], _ b: [UInt8], width: Int, height: Int) -> CIImage {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            rgba[i * 4] = r[i]
            rgba[i * 4 + 1] = g[i]
            rgba[i * 4 + 2] = b[i]
        }
        let data = Data(rgba)
        // Rows are top-down (Core Graphics bitmap order), which is what this initializer expects.
        return CIImage(bitmapData: data, bytesPerRow: width * 4, size: CGSize(width: width, height: height), format: .RGBA8, colorSpace: nil)
    }
}
