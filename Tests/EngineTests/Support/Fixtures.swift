import CoreImage
import Foundation
import LumoraCore
@testable import LumoraEngine

private final class FixtureBundleMarker {}

/// Real photos from Fixtures/Photos (see CREDITS.md there).
enum Fixtures {
    static func photo(_ name: String) -> CIImage {
        let bundle = Bundle(for: FixtureBundleMarker.self)
        guard let url = bundle.url(forResource: name, withExtension: "jpg", subdirectory: "Photos")
                ?? bundle.url(forResource: name, withExtension: "jpg"),
              let data = try? Data(contentsOf: url),
              let source = ImageSource(data: data) else {
            fatalError("Missing fixture photo \(name)")
        }
        return source.original
    }

    private struct FaceRecord: Decodable {
        var bounds: [Double]
        var contour, leftEye, rightEye, leftBrow, rightBrow, nose, noseCrest, outerLips, innerLips: [[Double]]
        var leftPupil: [Double]?
        var rightPupil: [Double]?
        var roll: Double
    }

    private struct BodyRecord: Decodable {
        var joints: [String: [Double]]
    }

    private struct PhotoRecord: Decodable {
        var file: String
        var faces: [FaceRecord]
        var bodies: [BodyRecord]
    }

    /// Reference analysis made with real Apple Vision on macOS (scripts/reference_analysis.swift).
    private static let reference: [String: PhotoRecord] = {
        let bundle = Bundle(for: FixtureBundleMarker.self)
        guard let url = bundle.url(forResource: "reference", withExtension: "json", subdirectory: "Photos")
                ?? bundle.url(forResource: "reference", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([PhotoRecord].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: records.map { ($0.file.replacingOccurrences(of: ".jpg", with: ""), $0) })
    }()

    /// Reference face landmarks for a fixture photo (left to right).
    static func faces(_ name: String) -> [FaceLandmarks] {
        guard let record = reference[name] else { return [] }
        func points(_ list: [[Double]]) -> [SIMD2<Double>] { list.map { SIMD2($0[0], $0[1]) } }
        let faces = record.faces.map { face -> FaceLandmarks in
            var eyes = [points(face.leftEye), points(face.rightEye)]
            var brows = [points(face.leftBrow), points(face.rightBrow)]
            var pupils = [face.leftPupil.map { SIMD2($0[0], $0[1]) }, face.rightPupil.map { SIMD2($0[0], $0[1]) }]
            if FaceLandmarks.centroid(eyes[0]).x > FaceLandmarks.centroid(eyes[1]).x {
                eyes.swapAt(0, 1)
                brows.swapAt(0, 1)
                pupils.swapAt(0, 1)
            }
            return FaceLandmarks(
                bounds: CGRectValue(x: face.bounds[0], y: face.bounds[1], width: face.bounds[2], height: face.bounds[3]),
                contour: points(face.contour),
                leftEye: eyes[0],
                rightEye: eyes[1],
                leftBrow: brows[0],
                rightBrow: brows[1],
                nose: points(face.nose),
                noseCrest: points(face.noseCrest),
                outerLips: points(face.outerLips),
                innerLips: points(face.innerLips),
                leftPupil: pupils[0],
                rightPupil: pupils[1],
                roll: face.roll
            )
        }
        return faces.sorted { $0.bounds.midX < $1.bounds.midX }
    }

    /// Reference body-pose joints (name -> normalized point) for each person in a fixture photo.
    static func bodies(_ name: String) -> [[String: SIMD2<Double>]] {
        guard let record = reference[name] else { return [] }
        return record.bodies.map { body in body.joints.mapValues { SIMD2($0[0], $0[1]) } }
    }

    static var hasReference: Bool { !reference.isEmpty }

    /// Reference person mask (from macOS Vision) for a fixture photo, if generated.
    static func personMask(_ name: String) -> CIImage? {
        let bundle = Bundle(for: FixtureBundleMarker.self)
        guard let url = bundle.url(forResource: "\(name)-person", withExtension: "png", subdirectory: "Photos")
                ?? bundle.url(forResource: "\(name)-person", withExtension: "png") else { return nil }
        return CIImage(contentsOf: url, options: [.colorSpace: NSNull()])
    }

    /// Reference body poses for a fixture photo.
    static func poses(_ name: String) -> [BodyPose] {
        bodies(name).map { joints in
            var mapped: [BodyJoint: SIMD2<Double>] = [:]
            for (name, point) in joints {
                if let joint = BodyJoint(rawValue: name) { mapped[joint] = point }
            }
            return BodyPose(joints: mapped)
        }
        .filter { $0.hipCenter != nil && $0.shoulderCenter != nil }
        .sorted { ($0.hipCenter?.x ?? 0) < ($1.hipCenter?.x ?? 0) }
    }

    /// Analysis of a fixture photo using the reference landmarks, poses and person mask.
    static func analysis(_ name: String, image: CIImage) -> ImageAnalysis {
        ImageAnalysis(
            image: image,
            faceLandmarks: hasReference ? faces(name) : nil,
            personMask: personMask(name),
            bodyPoses: hasReference ? poses(name) : nil
        )
    }

    /// Crop around a normalized rect (y up), scaled so the long side is `size` pixels.
    static func crop(_ image: CIImage, normalized rect: (x: Double, y: Double, width: Double, height: Double), size: CGFloat = 420) -> CIImage {
        let extent = image.extent
        let pixels = CGRect(
            x: extent.minX + CGFloat(rect.x) * extent.width,
            y: extent.minY + CGFloat(rect.y) * extent.height,
            width: CGFloat(rect.width) * extent.width,
            height: CGFloat(rect.height) * extent.height
        ).intersection(extent)
        let scale = size / max(pixels.width, pixels.height)
        return image.cropped(to: pixels)
            .transformed(by: CGAffineTransform(translationX: -pixels.minX, y: -pixels.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}
