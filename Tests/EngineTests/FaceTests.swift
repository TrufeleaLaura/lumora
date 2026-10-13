import CoreImage
import LumoraCore
import XCTest
@testable import LumoraEngine

final class FaceTests: XCTestCase {
    private static let portrait = Fixtures.photo("portrait-woman")
    private static let portraitAnalysis = ImageAnalysis(image: portrait)
    private static let smile = Fixtures.photo("portrait-smile")
    private static let smileAnalysis = ImageAnalysis(image: smile)
    private static let group = Fixtures.photo("group")
    private static let groupAnalysis = ImageAnalysis(image: group)

    private func render(_ image: CIImage, _ analysis: ImageAnalysis, _ change: (inout FaceRetouchSettings) -> Void) -> CIImage {
        var document = EditDocument()
        change(&document.beauty.allFaces)
        return RenderPipeline().apply(document, to: image, analysis: analysis)
    }

    private func pixelRect(_ points: [SIMD2<Double>], in image: CIImage, grow: Double = 0) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        let extent = image.extent
        return CGRect(
            x: CGFloat(xs.min()! - grow) * extent.width,
            y: CGFloat(ys.min()! - grow) * extent.height,
            width: CGFloat(xs.max()! - xs.min()! + 2 * grow) * extent.width,
            height: CGFloat(ys.max()! - ys.min()! + 2 * grow) * extent.height
        )
    }

    // MARK: - Infrastructure

    func testBitmapDataRowsAreTopDown() {
        // Two rows: memory row 0 white, row 1 black. Top-down means white is at the top (y = 1).
        let bytes: [UInt8] = [255, 255, 255, 255, 0, 0, 0, 255]
        let image = CIImage(bitmapData: Data(bytes), bytesPerRow: 4, size: CGSize(width: 1, height: 2), format: .RGBA8, colorSpace: nil)
        let top = ImageStats.averageColor(of: image.cropped(to: CGRect(x: 0, y: 1, width: 1, height: 1)))
        let bottom = ImageStats.averageColor(of: image.cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)))
        XCTAssertGreaterThan(top.x, 0.9, "memory row 0 should be the top row")
        XCTAssertLessThan(bottom.x, 0.1)
    }

    func testDisplacementMovesContentTheRightWay() {
        // Shift everything inside a region 20 px to the right: output at x samples input at x - 20.
        let image = TestScene.image()
        let width = Double(image.extent.width)
        let field = DisplacementField(
            region: CGRectValue(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
            columns: 3,
            rows: 3,
            offsets: Array(repeating: SIMD2(Float(-20 / width), 0), count: 9)
        )
        let warped = RenderPipeline().applyDisplacement(field, to: image)
        let probe = CGRect(x: 480, y: 300, width: 6, height: 6)
        let expected = ImageStats.averageColor(of: image.cropped(to: probe.offsetBy(dx: -20, dy: 0)))
        let actual = ImageStats.averageColor(of: warped.cropped(to: probe))
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.03)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.03)
        XCTAssertEqual(warped.extent, image.extent)
    }

    // MARK: - Detection

    func testDetectsFaces() {
        XCTAssertEqual(Self.portraitAnalysis.faces.count, 1)
        XCTAssertEqual(Self.smileAnalysis.faces.count, 1)
        XCTAssertGreaterThanOrEqual(Self.groupAnalysis.faces.count, 3)
        let face = Self.portraitAnalysis.faces[0].landmarks
        XCTAssertFalse(face.contour.isEmpty)
        XCTAssertFalse(face.outerLips.isEmpty)
        XCTAssertLessThan(FaceLandmarks.centroid(face.leftEye).x, FaceLandmarks.centroid(face.rightEye).x)
        // Eyes above the mouth (y up).
        XCTAssertGreaterThan(FaceLandmarks.centroid(face.leftEye).y, FaceLandmarks.centroid(face.outerLips).y)
        // Skin tone is a plausible skin color (OKLab: light, slightly red/yellow).
        let tone = Self.portraitAnalysis.faces[0].skinTone
        XCTAssertGreaterThan(tone.x, 0.4)
        XCTAssertGreaterThan(tone.y, 0)
        XCTAssertGreaterThan(tone.z, 0)
    }

    // MARK: - Retouch

    func testSmoothingReducesSkinDetailButNotEyes() {
        let face = Self.portraitAnalysis.faces[0].landmarks
        let smoothed = render(Self.portrait, Self.portraitAnalysis) { $0.smooth = 100; $0.texture = 30 }
        // Cheek patch below the left eye.
        let eye = FaceLandmarks.centroid(face.leftEye)
        let mouth = FaceLandmarks.centroid(face.outerLips)
        let cheekCenter = SIMD2(eye.x, eye.y - (eye.y - mouth.y) * 0.55)
        let cheek = pixelRect([cheekCenter], in: Self.portrait, grow: face.bounds.width * 0.06)
        let before = ImageStats.noiseLevel(of: Self.portrait.cropped(to: cheek))
        let after = ImageStats.noiseLevel(of: smoothed.cropped(to: cheek))
        XCTAssertLessThan(after, before * 0.75)

        let eyeRect = pixelRect(face.rightEye, in: Self.portrait)
        let eyeBefore = ImageStats.noiseLevel(of: Self.portrait.cropped(to: eyeRect))
        let eyeAfter = ImageStats.noiseLevel(of: smoothed.cropped(to: eyeRect))
        XCTAssertGreaterThan(eyeAfter, eyeBefore * 0.8, "eyes must stay sharp")
    }

    func testTeethWhiteningRemovesYellow() {
        let face = Self.smileAnalysis.faces[0].landmarks
        let mouth = pixelRect(face.innerLips, in: Self.smile)
        let before = ImageStats.averageColor(of: Self.smile.cropped(to: mouth))
        let after = ImageStats.averageColor(of: render(Self.smile, Self.smileAnalysis) { $0.teethWhiten = 100 }.cropped(to: mouth))
        let labBefore = ColorMath.linearSRGBToOklab(Double(before.x), Double(before.y), Double(before.z))
        let labAfter = ColorMath.linearSRGBToOklab(Double(after.x), Double(after.y), Double(after.z))
        XCTAssertLessThan(labAfter.2, labBefore.2, "less yellow")
        XCTAssertGreaterThanOrEqual(labAfter.0, labBefore.0 - 0.005, "not darker")
    }

    // MARK: - Reshape

    func testSlimFaceOnlyChangesTheFaceArea() {
        let slim = render(Self.portrait, Self.portraitAnalysis) { $0.faceSlim = 100; $0.jaw = 60 }
        let corner = CGRect(x: 0, y: 0, width: 60, height: 60)
        let a = ImageStats.averageColor(of: Self.portrait.cropped(to: corner))
        let b = ImageStats.averageColor(of: slim.cropped(to: corner))
        XCTAssertEqual(a.x, b.x, accuracy: 0.001)

        let face = Self.portraitAnalysis.faces[0].landmarks
        let jaw = pixelRect(face.contour, in: Self.portrait)
        let difference = ImageStats.averageColor(of: slim.cropped(to: jaw).applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: Self.portrait.cropped(to: jaw)]))
        XCTAssertGreaterThan(difference.x + difference.y + difference.z, 0.01)
    }

    func testPerFaceEditsOnlyTouchThatFace() {
        let faces = Self.groupAnalysis.faces
        guard faces.count >= 2 else { return XCTFail("need two faces") }
        var document = EditDocument()
        var settings = FaceRetouchSettings()
        settings.faceSlim = 100
        settings.eyeSize = 80
        document.beauty.faces = [FaceEdit(anchor: faces[0].landmarks.anchor, settings: settings)]
        let output = RenderPipeline().apply(document, to: Self.group, analysis: Self.groupAnalysis)
        let other = pixelRect(faces[1].landmarks.contour + faces[1].landmarks.leftEye, in: Self.group)
        let a = ImageStats.averageColor(of: output.cropped(to: other))
        let b = ImageStats.averageColor(of: Self.group.cropped(to: other))
        XCTAssertEqual(a.x, b.x, accuracy: 0.002)
        let first = pixelRect(faces[0].landmarks.leftEye, in: Self.group, grow: faces[0].landmarks.bounds.width * 0.05)
        let c = ImageStats.averageColor(of: output.cropped(to: first).applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: Self.group.cropped(to: first)]))
        XCTAssertGreaterThan(c.x + c.y + c.z, 0.005)
    }

    // MARK: - Diagnostics

    /// Landmarks drawn as dots: contour red, eyes yellow, brows orange, lips green, nose blue, pupils white.
    private func landmarkOverlay(_ image: CIImage, _ analysis: ImageAnalysis) -> CIImage {
        var output = image
        let extent = image.extent
        let dotRadius = max(3, extent.width * 0.004)
        func dot(_ p: SIMD2<Double>, _ color: CIColor) {
            let center = CGPoint(x: extent.minX + CGFloat(p.x) * extent.width, y: extent.minY + CGFloat(p.y) * extent.height)
            let disc = CIImage(color: color).cropped(to: CGRect(x: center.x - dotRadius, y: center.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
            output = disc.composited(over: output)
        }
        for face in analysis.faces {
            let f = face.landmarks
            print("FACE bounds=\(f.bounds) leftEye=\(FaceLandmarks.centroid(f.leftEye)) rightEye=\(FaceLandmarks.centroid(f.rightEye)) lips=\(FaceLandmarks.centroid(f.outerLips)) contour=\(f.contour.count) pts")
            f.contour.forEach { dot($0, CIColor(red: 1, green: 0, blue: 0)) }
            (f.leftEye + f.rightEye).forEach { dot($0, CIColor(red: 1, green: 1, blue: 0)) }
            (f.leftBrow + f.rightBrow).forEach { dot($0, CIColor(red: 1, green: 0.5, blue: 0)) }
            (f.outerLips + f.innerLips).forEach { dot($0, CIColor(red: 0, green: 1, blue: 0)) }
            (f.nose + f.noseCrest).forEach { dot($0, CIColor(red: 0, green: 0.4, blue: 1)) }
            [f.leftPupil, f.rightPupil].compactMap { $0 }.forEach { dot($0, CIColor(red: 1, green: 1, blue: 1)) }
            let b = f.bounds
            let corners = [SIMD2(b.x, b.y), SIMD2(b.x + b.width, b.y), SIMD2(b.x, b.y + b.height), SIMD2(b.x + b.width, b.y + b.height)]
            corners.forEach { dot($0, CIColor(red: 1, green: 0, blue: 1)) }
        }
        return output
    }

    func testWriteLandmarkSheet() throws {
        try ContactSheet.write([
            ("Portrait landmarks", landmarkOverlay(Self.portrait, Self.portraitAnalysis)),
            ("Smile landmarks", landmarkOverlay(Self.smile, Self.smileAnalysis)),
            ("Group landmarks", landmarkOverlay(Self.group, Self.groupAnalysis)),
        ], name: "19-face-landmarks", columns: 3)
    }

    // MARK: - Contact sheets

    private func faceCrop(_ image: CIImage, _ analysis: ImageAnalysis, index: Int = 0, grow: Double = 1.7) -> CIImage {
        let bounds = analysis.faces[index].landmarks.bounds.expanded(by: grow)
        return Fixtures.crop(image, normalized: (bounds.x, bounds.y, bounds.width, bounds.height))
    }

    /// Masks drawn over the photo: skin red, lips green, mouth blue, eyes yellow, iris magenta, under-eye cyan.
    private func maskOverlay(_ image: CIImage, _ analysis: ImageAnalysis) -> CIImage {
        var output = image
        for face in analysis.faces {
            let a = RenderPipeline.place(face.masksA, region: face.maskRegion, in: image.extent)
            let b = RenderPipeline.place(face.masksB, region: face.maskRegion, in: image.extent)
            func tint(_ mask: CIImage, channel: Int, color: (CGFloat, CGFloat, CGFloat)) -> CIImage {
                let pick = [CIVector(x: 1, y: 0, z: 0, w: 0), CIVector(x: 0, y: 1, z: 0, w: 0), CIVector(x: 0, y: 0, z: 1, w: 0)][channel]
                return mask.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: pick.x * color.0, y: pick.y * color.0, z: pick.z * color.0, w: 0),
                    "inputGVector": CIVector(x: pick.x * color.1, y: pick.y * color.1, z: pick.z * color.1, w: 0),
                    "inputBVector": CIVector(x: pick.x * color.2, y: pick.y * color.2, z: pick.z * color.2, w: 0),
                    "inputAVector": CIVector(x: pick.x * 0.45, y: pick.y * 0.45, z: pick.z * 0.45, w: 0),
                ]).premultiplyingAlpha()
            }
            for overlay in [tint(a, channel: 0, color: (1, 0, 0)), tint(a, channel: 1, color: (0, 1, 0)), tint(a, channel: 2, color: (0, 0, 1)),
                            tint(b, channel: 0, color: (1, 1, 0)), tint(b, channel: 1, color: (1, 0, 1)), tint(b, channel: 2, color: (0, 1, 1))] {
                output = overlay.composited(over: output)
            }
        }
        return output
    }

    func testWritePortraitSheet() throws {
        let image = Self.portrait
        let analysis = Self.portraitAnalysis
        func edit(_ change: (inout FaceRetouchSettings) -> Void) -> CIImage {
            faceCrop(render(image, analysis, change), analysis)
        }
        try ContactSheet.write([
            ("Original", faceCrop(image, analysis)),
            ("Masks", faceCrop(maskOverlay(image, analysis), analysis)),
            ("Auto beauty", edit { $0 = FaceCatalog.autoBeauty }),
            ("Smooth 100", edit { $0.smooth = 100 }),
            ("Eyes: brighten, whiten", edit { $0.eyeBrighten = 80; $0.eyeWhiten = 80 }),
            ("Iris blue", edit { $0.irisColor = 80; $0.irisHue = 210 }),
            ("Slim 80 + jaw 60", edit { $0.faceSlim = 80; $0.jaw = 60 }),
            ("Eyes +60", edit { $0.eyeSize = 60 }),
            ("Nose -60 width, -40 length", edit { $0.noseWidth = -60; $0.noseLength = -40 }),
            ("Lips +70, smile +60", edit { $0.lipsFullness = 70; $0.smile = 60 }),
            ("Chin +60, forehead -50", edit { $0.chin = 60; $0.forehead = -50 }),
            ("Cheekbones +70", edit { $0.cheekbones = 70 }),
        ], name: "20-face-portrait")
    }

    func testWriteSmileAndGroupSheet() throws {
        try ContactSheet.write([
            ("Original", faceCrop(Self.smile, Self.smileAnalysis)),
            ("Masks", faceCrop(maskOverlay(Self.smile, Self.smileAnalysis), Self.smileAnalysis)),
            ("Teeth 100", faceCrop(render(Self.smile, Self.smileAnalysis) { $0.teethWhiten = 100 }, Self.smileAnalysis)),
            ("Auto beauty", faceCrop(render(Self.smile, Self.smileAnalysis) { $0 = FaceCatalog.autoBeauty }, Self.smileAnalysis)),
            ("Group", Self.group),
            ("Group masks", maskOverlay(Self.group, Self.groupAnalysis)),
            ("Group auto beauty", render(Self.group, Self.groupAnalysis) { $0 = FaceCatalog.autoBeauty }),
            ("Group slim + eyes", render(Self.group, Self.groupAnalysis) { $0.faceSlim = 70; $0.eyeSize = 50 }),
        ], name: "21-face-smile-group")
    }
}
