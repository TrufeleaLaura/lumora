import CoreImage
import LumoraCore
import XCTest
@testable import LumoraEngine

final class MaskTests: XCTestCase {
    private let pipeline = RenderPipeline()
    private static let scene = TestScene.image()
    private static let sceneAnalysis = ImageAnalysis(image: scene)
    private static let portrait = Fixtures.photo("portrait-woman")
    private static let portraitAnalysis = Fixtures.analysis("portrait-woman", image: portrait)
    private static let body = Fixtures.photo("body-front")
    private static let bodyAnalysis = Fixtures.analysis("body-front", image: body)

    private func average(_ image: CIImage, _ rect: CGRect) -> Float {
        ImageStats.averageColor(of: image.cropped(to: rect)).x
    }

    private func mask(_ components: [MaskComponent], _ image: CIImage, _ analysis: ImageAnalysis) -> CIImage {
        pipeline.maskImage(Mask(components: components), reference: image, analysis: analysis)
    }

    private func normalizedRect(_ center: SIMD2<Double>, size: Double, in image: CIImage) -> CGRect {
        let e = image.extent
        return CGRect(x: e.minX + CGFloat(center.x - size / 2) * e.width, y: e.minY + CGFloat(center.y - size / 2) * e.height,
                      width: CGFloat(size) * e.width, height: CGFloat(size) * e.height)
    }

    func testLinearAndRadialMasks() {
        let image = Self.scene
        var linear = MaskCatalog.component(.linear)
        linear.start = SIMD2(0.5, 0.9)
        linear.end = SIMD2(0.5, 0.6)
        let gradient = mask([linear], image, Self.sceneAnalysis)
        XCTAssertGreaterThan(average(gradient, CGRect(x: 100, y: 600, width: 700, height: 30)), 0.99)
        XCTAssertLessThan(average(gradient, CGRect(x: 100, y: 50, width: 700, height: 300)), 0.01)
        XCTAssertEqual(average(gradient, CGRect(x: 100, y: 479, width: 700, height: 2)), 0.5, accuracy: 0.05)

        var radial = MaskCatalog.component(.radial)
        radial.start = SIMD2(0.5, 0.5)
        radial.radius = SIMD2(0.2, 0.1)
        radial.feather = 20
        let ellipse = mask([radial], image, Self.sceneAnalysis)
        XCTAssertGreaterThan(average(ellipse, CGRect(x: 460, y: 300, width: 40, height: 40)), 0.99)
        // 0.2 × 960 = 192 px wide, 0.1 × 960 = 96 px tall.
        XCTAssertGreaterThan(average(ellipse, CGRect(x: 610, y: 315, width: 10, height: 10)), 0.95)
        XCTAssertLessThan(average(ellipse, CGRect(x: 470, y: 440, width: 20, height: 20)), 0.01)
        XCTAssertLessThan(average(ellipse, CGRect(x: 0, y: 0, width: 50, height: 50)), 0.001)

        // Subtracting the ellipse from the gradient, and intersecting.
        var hole = radial
        hole.mode = .subtract
        hole.start = SIMD2(0.5, 0.95)
        let combined = mask([linear, hole], image, Self.sceneAnalysis)
        XCTAssertLessThan(average(combined, CGRect(x: 460, y: 600, width: 40, height: 20)), 0.01)
        XCTAssertGreaterThan(average(combined, CGRect(x: 40, y: 600, width: 40, height: 20)), 0.99)
        var inverted = radial
        inverted.inverted = true
        let invertedMask = mask([inverted], image, Self.sceneAnalysis)
        XCTAssertLessThan(average(invertedMask, CGRect(x: 460, y: 300, width: 40, height: 40)), 0.01)
    }

    func testColorAndLuminanceRanges() {
        let image = Self.scene
        // Sample the blue patch (index 4) color in OKLab.
        let blue = ImageStats.averageColor(of: image.cropped(to: TestScene.patchRect(4)))
        let lab = ColorMath.linearSRGBToOklab(Double(blue.x), Double(blue.y), Double(blue.z))
        var range = MaskCatalog.component(.color)
        range.colors = [SIMD3(lab.0, lab.1, lab.2)]
        range.refine = 30
        let selected = mask([range], image, Self.sceneAnalysis)
        XCTAssertGreaterThan(average(selected, TestScene.patchRect(4)), 0.9)
        XCTAssertLessThan(average(selected, TestScene.patchRect(0)), 0.05)
        XCTAssertLessThan(average(selected, TestScene.patchRect(3)), 0.05)
        XCTAssertLessThan(average(selected, TestScene.groundRect), 0.05)

        var bright = MaskCatalog.component(.luminance)
        bright.range = SIMD2(0.8, 1)
        bright.refine = 10
        let highlights = mask([bright], image, Self.sceneAnalysis)
        XCTAssertGreaterThan(average(highlights, TestScene.sunRect), 0.9)
        XCTAssertLessThan(average(highlights, TestScene.shadowRect), 0.01)
        XCTAssertLessThan(average(highlights, TestScene.groundRect), 0.05)
    }

    func testSkyIsFoundAboveTheMountains() throws {
        let sky = mask([MaskCatalog.component(.sky)], Self.scene, Self.sceneAnalysis)
        XCTAssertNotNil(Self.sceneAnalysis.skyCoefficients)
        XCTAssertGreaterThan(average(sky, TestScene.skyRect), 0.85)
        XCTAssertGreaterThan(average(sky, TestScene.sunRect), 0.7, "the sun is part of the sky")
        XCTAssertLessThan(average(sky, TestScene.mountainRect), 0.15)
        XCTAssertLessThan(average(sky, TestScene.groundRect), 0.05)
        XCTAssertLessThan(average(sky, TestScene.shadowRect), 0.05)
    }

    func testLocalExposureOnlyInsideTheMask() {
        var document = EditDocument()
        var radial = MaskCatalog.component(.radial)
        radial.start = SIMD2(0.3, 0.3)
        radial.radius = SIMD2(0.1, 0.1)
        radial.feather = 10
        var spot = Mask(components: [radial])
        spot.adjustments.exposure = 1
        document.masks = [spot]
        let output = pipeline.apply(document, to: Self.scene, analysis: Self.sceneAnalysis)
        let center = CGRect(x: 268, y: 172, width: 20, height: 20)
        let before = ImageStats.averageLuminance(of: Self.scene.cropped(to: center))
        let after = ImageStats.averageLuminance(of: output.cropped(to: center))
        XCTAssertEqual(after / before, 2, accuracy: 0.25, "+1 EV doubles linear light")
        let outside = TestScene.sunRect
        XCTAssertEqual(ImageStats.averageLuminance(of: output.cropped(to: outside)), ImageStats.averageLuminance(of: Self.scene.cropped(to: outside)), accuracy: 0.002)

        // Hidden masks and amount 0 do nothing.
        document.masks[0].isVisible = false
        XCTAssertEqual(ImageStats.averageLuminance(of: pipeline.apply(document, to: Self.scene, analysis: Self.sceneAnalysis).cropped(to: center)), before, accuracy: 0.002)
    }

    func testBrushMaskFollowsStrokes() {
        var brush = MaskCatalog.component(.brush)
        brush.strokes = [BrushStroke(points: [SIMD2(0.1, 0.5), SIMD2(0.9, 0.5)], radius: 0.03, feather: 0)]
        let painted = mask([brush], Self.scene, Self.sceneAnalysis)
        XCTAssertGreaterThan(average(painted, CGRect(x: 300, y: 315, width: 300, height: 10)), 0.97)
        XCTAssertLessThan(average(painted, CGRect(x: 300, y: 400, width: 300, height: 40)), 0.01)
    }

    func testPeopleAndSubjectMasks() throws {
        try XCTSkipUnless(Fixtures.hasReference, "reference.json is generated on CI")
        let face = Self.portraitAnalysis.faces[0].landmarks
        var lips = MaskCatalog.component(.people)
        lips.parts = [.lips]
        let lipsMask = mask([lips], Self.portrait, Self.portraitAnalysis)
        let mouth = FaceLandmarks.centroid(face.outerLips)
        let eye = FaceLandmarks.centroid(face.leftEye)
        // Middle of the lower lip (the mouth may be slightly open at the centroid).
        let lowest = try XCTUnwrap(face.outerLips.min { $0.y < $1.y })
        let lowerLip = (lowest + mouth) / 2
        XCTAssertGreaterThan(average(lipsMask, normalizedRect(lowerLip, size: 0.003, in: Self.portrait)), 0.5)
        XCTAssertLessThan(average(lipsMask, normalizedRect(eye, size: 0.01, in: Self.portrait)), 0.05)

        var skin = MaskCatalog.component(.people)
        skin.parts = [.faceSkin]
        let skinMask = mask([skin], Self.portrait, Self.portraitAnalysis)
        let cheek = SIMD2(eye.x, eye.y - (eye.y - mouth.y) * 0.5)
        XCTAssertGreaterThan(average(skinMask, normalizedRect(cheek, size: 0.01, in: Self.portrait)), 0.6)
        XCTAssertLessThan(average(skinMask, normalizedRect(eye, size: 0.006, in: Self.portrait)), 0.2)
        XCTAssertLessThan(average(skinMask, CGRect(x: 0, y: 0, width: 40, height: 40)), 0.01)

        // Subject on the full-body photo: the torso is in, the backdrop corner is out.
        let shape = try XCTUnwrap(Self.bodyAnalysis.bodies.first)
        let hips = try XCTUnwrap(shape.pose.hipCenter)
        let subject = mask([MaskCatalog.component(.subject)], Self.body, Self.bodyAnalysis)
        XCTAssertGreaterThan(average(subject, normalizedRect(hips, size: 0.02, in: Self.body)), 0.8)
        XCTAssertLessThan(average(subject, CGRect(x: 0, y: 0, width: 30, height: 30)), 0.05)
        let background = mask([MaskCatalog.component(.background)], Self.body, Self.bodyAnalysis)
        XCTAssertLessThan(average(background, normalizedRect(hips, size: 0.02, in: Self.body)), 0.2)
    }

    // MARK: - Contact sheet

    private func overlay(_ components: [MaskComponent], _ image: CIImage, _ analysis: ImageAnalysis) -> CIImage {
        pipeline.maskOverlay(Mask(components: components), on: image, reference: image, analysis: analysis)
    }

    private func edit(_ image: CIImage, _ analysis: ImageAnalysis, _ components: [MaskComponent], _ change: (inout LocalAdjustments) -> Void) -> CIImage {
        var document = EditDocument()
        var mask = Mask(components: components)
        change(&mask.adjustments)
        document.masks = [mask]
        return pipeline.apply(document, to: image, analysis: analysis)
    }

    private func people(_ parts: [PersonPart]) -> MaskComponent {
        var component = MaskCatalog.component(.people)
        component.parts = parts
        return component
    }

    func testWriteMaskSheets() throws {
        let scene = Self.scene
        let sky = [MaskCatalog.component(.sky)]
        var gradient = MaskCatalog.component(.linear)
        gradient.start = SIMD2(0.5, 0.0)
        gradient.end = SIMD2(0.5, 0.45)
        var radial = MaskCatalog.component(.radial)
        radial.start = SIMD2(0.75, 0.8)
        radial.radius = SIMD2(0.18, 0.12)
        var luminance = MaskCatalog.component(.luminance)
        luminance.range = SIMD2(0, 0.25)
        try ContactSheet.write([
            ("Scene", scene),
            ("Sky mask", overlay(sky, scene, Self.sceneAnalysis)),
            ("Sky: darker, bluer", edit(scene, Self.sceneAnalysis, sky) { $0.exposure = -0.6; $0.temperature = -30; $0.saturation = 30 }),
            ("Ground gradient: warm", edit(scene, Self.sceneAnalysis, [gradient]) { $0.temperature = 50; $0.exposure = 0.3 }),
            ("Radial", overlay([radial], scene, Self.sceneAnalysis)),
            ("Shadows range", overlay([luminance], scene, Self.sceneAnalysis)),
            ("Shadows range: lift", edit(scene, Self.sceneAnalysis, [luminance]) { $0.exposure = 1; $0.noise = 60 }),
            ("Point on sun", edit(scene, Self.sceneAnalysis, [radial]) { $0.colorAmount = 80; $0.colorHue = 30 }),
        ], name: "40-masks-scene", columns: 4)

        guard Fixtures.hasReference else { return }
        let portrait = Self.portrait
        let analysis = Self.portraitAnalysis
        let crop = { (image: CIImage) -> CIImage in
            guard let face = analysis.faces.first?.landmarks.bounds else { return image }
            let region = face.expanded(by: 2.4)
            return Fixtures.crop(image, normalized: (region.x, region.y, region.width, region.height))
        }
        try ContactSheet.write([
            ("Portrait", crop(portrait)),
            ("Subject", crop(overlay([MaskCatalog.component(.subject)], portrait, analysis))),
            ("Sky", crop(overlay(sky, portrait, analysis))),
            ("Face skin", crop(overlay([people([.faceSkin])], portrait, analysis))),
            ("Hair", crop(overlay([people([.hair])], portrait, analysis))),
            ("Eyes, iris, brows", crop(overlay([people([.eyes, .iris, .brows])], portrait, analysis))),
            ("Lips + teeth", crop(overlay([people([.lips, .teeth])], portrait, analysis))),
            ("Clothes", crop(overlay([people([.clothes])], portrait, analysis))),
            ("Background darker", crop(edit(portrait, analysis, [MaskCatalog.component(.background)]) { $0.exposure = -0.8; $0.saturation = -40; $0.sharpness = -60 })),
            ("Hair: warmer, glossy", crop(edit(portrait, analysis, [people([.hair])]) { $0.colorAmount = 60; $0.colorHue = 25; $0.clarity = 30 })),
            ("Brows darker", crop(edit(portrait, analysis, [people([.brows])]) { $0.exposure = -0.7 })),
            ("Sky warmer", crop(edit(portrait, analysis, sky) { $0.temperature = 40; $0.exposure = -0.3 })),
        ], name: "41-masks-people", columns: 4)

        let body = Self.body
        try ContactSheet.write([
            ("Body", body),
            ("Body skin", overlay([people([.bodySkin])], body, Self.bodyAnalysis)),
            ("Clothes", overlay([people([.clothes])], body, Self.bodyAnalysis)),
            ("Subject", overlay([MaskCatalog.component(.subject)], body, Self.bodyAnalysis)),
        ], name: "42-masks-body", columns: 4)
    }
}
