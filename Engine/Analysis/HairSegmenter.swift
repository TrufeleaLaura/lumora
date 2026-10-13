import CoreImage
import Foundation
import LumoraCore

/// Hair mask for photos without an embedded hair matte: grown from the hair around each face
/// through connected, hair-colored pixels of the person, so ponytails and long hair are found.
enum HairSegmenter {
    static func mask(faces: [FaceInfo], person: CIImage?, image: CIImage, context: CIContext) -> CIImage? {
        guard !faces.isEmpty else { return nil }
        let extent = image.extent
        let small = ImageSource.scaled(image, maxDimension: 384)
        let w = Int(small.extent.width), h = Int(small.extent.height)
        guard w > 8, h > 8 else { return nil }
        let grid = CGRect(x: 0, y: 0, width: w, height: h)
        func read(_ mask: CIImage?) -> [Float]? {
            guard let mask else { return nil }
            let stretched = ImageAnalysis.stretch(mask, over: grid)
            let data = RenderContext.readFloats(stretched, context: context)
            guard data.pixels.count == w * h * 4 else { return nil }
            return (0..<(w * h)).map { data.pixels[$0 * 4] }
        }
        let colors = RenderContext.readFloats(small, context: context)
        guard colors.pixels.count == w * h * 4 else { return nil }
        let personValues = read(person) ?? [Float](repeating: 1, count: w * h)

        var lab = [SIMD3<Float>](repeating: .zero, count: w * h)
        for i in 0..<(w * h) {
            let c = ColorMath.linearSRGBToOklab(Double(max(colors.pixels[i * 4], 0)), Double(max(colors.pixels[i * 4 + 1], 0)), Double(max(colors.pixels[i * 4 + 2], 0)))
            lab[i] = SIMD3(Float(c.0), Float(c.1), Float(c.2))
        }

        var hair = [Float](repeating: 0, count: w * h)
        for face in faces {
            guard let makeup = face.makeup else { continue }
            let faceArea = read(RenderPipeline.place(makeup.d, region: face.maskRegion, in: extent)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                    "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                ])
                .composited(over: RenderPipeline.black(extent))
                .cropped(to: extent)) ?? [Float](repeating: 0, count: w * h)
            let head = read(RenderPipeline.place(makeup.head, region: makeup.headRegion, in: extent)
                .composited(over: RenderPipeline.black(extent))
                .cropped(to: extent)) ?? [Float](repeating: 0, count: w * h)

            let tone = face.hairTone
            let skin = face.skinTone
            func hairDistance(_ c: SIMD3<Float>) -> Float {
                let d = c - tone
                return (d.x * d.x * 0.25 + d.y * d.y + d.z * d.z).squareRoot()
            }
            func skinLike(_ c: SIMD3<Float>) -> Bool {
                let d = SIMD2(c.y - skin.y, c.z - skin.z)
                return (d.x * d.x + d.y * d.y).squareRoot() < 0.05 && abs(c.x - skin.x) < 0.2
            }
            // Region limits: up to ~3.5 face widths from the face (long hair, ponytails).
            let center = SIMD2(Double(face.landmarks.bounds.midX) * Double(w), (1 - Double(face.landmarks.bounds.midY)) * Double(h))
            let reach = Double(face.landmarks.bounds.width) * Double(w) * 3.5

            var queue: [Int] = []
            var visited = [Bool](repeating: false, count: w * h)
            for i in 0..<(w * h) where head[i] > 0.5 && personValues[i] > 0.5 && faceArea[i] < 0.3 {
                let c = lab[i]
                if hairDistance(c) < 0.1 && !skinLike(c) {
                    visited[i] = true
                    queue.append(i)
                }
            }
            var index = 0
            while index < queue.count {
                let i = queue[index]
                index += 1
                hair[i] = 1
                let x = i % w, y = i / w
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    let j = ny * w + nx
                    guard !visited[j] else { continue }
                    visited[j] = true
                    let distanceFromFace = ((Double(nx) - center.x) * (Double(nx) - center.x) + (Double(ny) - center.y) * (Double(ny) - center.y)).squareRoot()
                    guard distanceFromFace < reach, personValues[j] > 0.4, faceArea[j] < 0.5 else { continue }
                    let c = lab[j]
                    // Farther from the head, demand a closer color match (avoid dark clothing).
                    let tolerance: Float = head[j] > 0.3 ? 0.15 : 0.11
                    if hairDistance(c) < tolerance && !skinLike(c) {
                        queue.append(j)
                    }
                }
            }
        }
        guard hair.contains(where: { $0 > 0 }) else { return nil }

        let bytes = hair.map { UInt8($0 * 255) }
        let raw = CIImage(bitmapData: Data(bytes), bytesPerRow: w, size: CGSize(width: w, height: h), format: .L8, colorSpace: nil)
        let soft = RenderContext.materialize(GuidedFilter.gaussian(raw, radius: 1.2), context: context)
        return ImageAnalysis.stretch(soft, over: extent).cropped(to: extent)
    }
}
