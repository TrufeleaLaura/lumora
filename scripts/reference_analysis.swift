// Runs Apple Vision on macOS (not the iOS simulator, whose face landmark model is broken)
// over the test photos and writes reference face landmarks and body-pose keypoints as JSON.
// Usage: swift scripts/reference_analysis.swift <photos folder> <output.json>
import CoreGraphics
import Foundation
import ImageIO
import Vision

struct FaceRecord: Codable {
    var bounds: [Double]
    var contour: [[Double]]
    var leftEye: [[Double]]
    var rightEye: [[Double]]
    var leftBrow: [[Double]]
    var rightBrow: [[Double]]
    var nose: [[Double]]
    var noseCrest: [[Double]]
    var outerLips: [[Double]]
    var innerLips: [[Double]]
    var leftPupil: [Double]?
    var rightPupil: [Double]?
    var roll: Double
}

struct BodyRecord: Codable {
    /// Joint name -> [x, y, confidence], normalized (y up).
    var joints: [String: [Double]]
}

struct PhotoRecord: Codable {
    var file: String
    var width: Int
    var height: Int
    var faces: [FaceRecord]
    var bodies: [BodyRecord]
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write("usage: reference_analysis <photos folder> <output.json>\n".data(using: .utf8)!)
    exit(1)
}
let folder = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
var records: [PhotoRecord] = []

let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.filter { $0.lowercased().hasSuffix(".jpg") }.sorted() ?? []
for file in files {
    let url = folder.appendingPathComponent(file)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let orientationValue = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1
    let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
    let swapped = orientationValue >= 5
    let size = CGSize(width: swapped ? image.height : image.width, height: swapped ? image.width : image.height)

    let faceRequest = VNDetectFaceLandmarksRequest()
    faceRequest.revision = VNDetectFaceLandmarksRequestRevision3
    let bodyRequest = VNDetectHumanBodyPoseRequest()
    let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
    do {
        try handler.perform([faceRequest, bodyRequest])
    } catch {
        FileHandle.standardError.write("Vision failed on \(file): \(error)\n".data(using: .utf8)!)
        continue
    }

    func points(_ region: VNFaceLandmarkRegion2D?) -> [[Double]] {
        guard let region else { return [] }
        return region.pointsInImage(imageSize: size).map { [Double($0.x / size.width), Double($0.y / size.height)] }
    }
    let faces: [FaceRecord] = (faceRequest.results ?? []).compactMap { face in
        guard let landmarks = face.landmarks else { return nil }
        let box = face.boundingBox
        return FaceRecord(
            bounds: [Double(box.minX), Double(box.minY), Double(box.width), Double(box.height)],
            contour: points(landmarks.faceContour),
            leftEye: points(landmarks.leftEye),
            rightEye: points(landmarks.rightEye),
            leftBrow: points(landmarks.leftEyebrow),
            rightBrow: points(landmarks.rightEyebrow),
            nose: points(landmarks.nose),
            noseCrest: points(landmarks.noseCrest),
            outerLips: points(landmarks.outerLips),
            innerLips: points(landmarks.innerLips),
            leftPupil: points(landmarks.leftPupil).first,
            rightPupil: points(landmarks.rightPupil).first,
            roll: face.roll?.doubleValue ?? 0
        )
    }
    let bodies: [BodyRecord] = (bodyRequest.results ?? []).map { body in
        var joints: [String: [Double]] = [:]
        if let recognized = try? body.recognizedPoints(.all) {
            for (name, point) in recognized where point.confidence > 0.1 {
                joints[name.rawValue.rawValue] = [Double(point.location.x), Double(point.location.y), Double(point.confidence)]
            }
        }
        return BodyRecord(joints: joints)
    }
    records.append(PhotoRecord(file: file, width: Int(size.width), height: Int(size.height), faces: faces, bodies: bodies))
    print("\(file): \(faces.count) face(s), \(bodies.count) body pose(s)")
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(records).write(to: output)
print("Wrote \(output.path)")
