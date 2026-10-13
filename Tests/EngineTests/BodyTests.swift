import CoreImage
import LumoraCore
import XCTest
@testable import LumoraEngine

final class BodyTests: XCTestCase {
    private static let front = Fixtures.photo("body-front")
    private static let frontAnalysis = Fixtures.analysis("body-front", image: front)
    private static let back = Fixtures.photo("body-back")
    private static let backAnalysis = Fixtures.analysis("body-back", image: back)
    private static let man = Fixtures.photo("body-man")
    private static let manAnalysis = Fixtures.analysis("body-man", image: man)

    private func render(_ image: CIImage, _ analysis: ImageAnalysis, _ change: (inout BodySettings) -> Void) -> CIImage {
        var document = EditDocument()
        change(&document.body.allBodies)
        return RenderPipeline().apply(document, to: image, analysis: analysis)
    }

    private func difference(_ a: CIImage, _ b: CIImage, _ rect: CGRect) -> Float {
        let d = ImageStats.averageColor(of: a.cropped(to: rect).applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: b.cropped(to: rect)]))
        return d.x + d.y + d.z
    }

    private func pixelRect(_ center: SIMD2<Double>, size: Double, in image: CIImage) -> CGRect {
        let e = image.extent
        return CGRect(x: CGFloat(center.x - size / 2) * e.width, y: CGFloat(center.y - size / 2) * e.height, width: CGFloat(size) * e.width, height: CGFloat(size) * e.height)
    }

    func testPosesAndOutlinesAreFound() throws {
        try XCTSkipUnless(Fixtures.hasReference, "reference.json is generated on CI")
        XCTAssertEqual(Self.frontAnalysis.bodies.count, 1)
        XCTAssertEqual(Self.backAnalysis.bodies.count, 1)
        let front = Self.frontAnalysis.bodies[0]
        XCTAssertFalse(front.pose.isBackView)
        XCTAssertTrue(Self.backAnalysis.bodies[0].pose.isBackView)
        // The waist is narrower than the shoulders on this photo.
        let waist = try XCTUnwrap(front.outline[.waist])
        let shoulders = try XCTUnwrap(front.outline[.shoulders])
        XCTAssertLessThan(abs(waist.second.x - waist.first.x), abs(shoulders.second.x - shoulders.first.x))
        XCTAssertNotNil(Self.frontAnalysis.personMask, "reference person mask expected")
    }

    func testSlimWaistOnlyChangesAroundTheBody() throws {
        try XCTSkipUnless(Fixtures.hasReference, "reference.json is generated on CI")
        let shape = Self.frontAnalysis.bodies[0]
        let output = render(Self.front, Self.frontAnalysis) { $0.waist = 100 }
        let waist = try XCTUnwrap(shape.outline[.waist])
        XCTAssertGreaterThan(difference(output, Self.front, pixelRect(waist.first, size: 0.06, in: Self.front)), 0.01)
        let corner = CGRect(x: 0, y: 0, width: 40, height: 40)
        XCTAssertLessThan(difference(output, Self.front, corner), 0.002)
    }

    func testLongerLegsMoveFeetDown() throws {
        try XCTSkipUnless(Fixtures.hasReference, "reference.json is generated on CI")
        let pose = Self.frontAnalysis.bodies[0].pose
        let field = try XCTUnwrap(BodyReshape.stretchField(for: pose, settings: { var s = BodySettings(); s.legs = 100; return s }()))
        // Below the hips, output pixels sample higher up (positive offset); the head is untouched.
        let ankle = try XCTUnwrap(pose[.leftAnkle])
        XCTAssertGreaterThan(field.offset(atX: 0.5, y: ankle.y).y, 0.005)
        let nose = try XCTUnwrap(pose[.nose])
        XCTAssertEqual(field.offset(atX: 0.5, y: nose.y).y, 0, accuracy: 1e-6)
    }

    // MARK: - Contact sheets

    private func edit(_ image: CIImage, _ analysis: ImageAnalysis, _ change: (inout BodySettings) -> Void) -> CIImage {
        render(image, analysis, change)
    }

    /// Outline points (yellow) and joints (red) for checking the measurements.
    private func outlineOverlay(_ image: CIImage, _ analysis: ImageAnalysis) -> CIImage {
        var output = image
        let e = image.extent
        let r = max(4, e.width * 0.006)
        func dot(_ p: SIMD2<Double>, _ color: CIColor) {
            let c = CGPoint(x: CGFloat(p.x) * e.width, y: CGFloat(p.y) * e.height)
            output = CIImage(color: color).cropped(to: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).composited(over: output)
        }
        for shape in analysis.bodies {
            shape.pose.joints.values.forEach { dot($0, CIColor(red: 1, green: 0, blue: 0)) }
            for pair in shape.outline.values {
                dot(pair.first, CIColor(red: 1, green: 1, blue: 0))
                dot(pair.second, CIColor(red: 1, green: 1, blue: 0))
            }
        }
        return output
    }

    func testWriteBodySheets() throws {
        try XCTSkipUnless(Fixtures.hasReference, "reference.json is generated on CI")
        try ContactSheet.write([
            ("Original", Self.front),
            ("Outline", outlineOverlay(Self.front, Self.frontAnalysis)),
            ("Slim waist 80", edit(Self.front, Self.frontAnalysis) { $0.waist = 80 }),
            ("Hips +70", edit(Self.front, Self.frontAnalysis) { $0.hips = 70 }),
            ("Bust +70", edit(Self.front, Self.frontAnalysis) { $0.bust = 70 }),
            ("Slim thighs 80", edit(Self.front, Self.frontAnalysis) { $0.thighs = 80 }),
            ("Longer legs 80", edit(Self.front, Self.frontAnalysis) { $0.legs = 80 }),
            ("Taller 80", edit(Self.front, Self.frontAnalysis) { $0.height = 80 }),
            ("Slim arms 80", edit(Self.front, Self.frontAnalysis) { $0.arms = 80 }),
            ("Shoulders +60", edit(Self.front, Self.frontAnalysis) { $0.shoulders = 60 }),
            ("Neck +70", edit(Self.front, Self.frontAnalysis) { $0.neck = 70 }),
            ("Head -50", edit(Self.front, Self.frontAnalysis) { $0.headSize = -50 }),
        ], name: "30-body-front", columns: 4)

        try ContactSheet.write([
            ("Original", Self.back),
            ("Outline", outlineOverlay(Self.back, Self.backAnalysis)),
            ("Butt +80", edit(Self.back, Self.backAnalysis) { $0.butt = 80 }),
            ("Butt lift +80", edit(Self.back, Self.backAnalysis) { $0.buttLift = 80 }),
            ("Waist 70 + hips 50", edit(Self.back, Self.backAnalysis) { $0.waist = 70; $0.hips = 50 }),
            ("Man: original", Self.man),
            ("Man: outline", outlineOverlay(Self.man, Self.manAnalysis)),
            ("Man: shoulders +60, waist 50", edit(Self.man, Self.manAnalysis) { $0.shoulders = 60; $0.waist = 50 }),
        ], name: "31-body-back-man", columns: 4)
    }
}
