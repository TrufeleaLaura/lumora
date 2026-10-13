import XCTest
@testable import LumoraCore

final class MaskTests: XCTestCase {
    private func value(_ coverage: [Float], width: Int, height: Int, at point: SIMD2<Double>) -> Float {
        let x = min(width - 1, Int(point.x * Double(width)))
        let y = min(height - 1, Int((1 - point.y) * Double(height)))
        return coverage[y * width + x]
    }

    func testBrushCoversItsPathOnly() {
        let stroke = BrushStroke(points: [SIMD2(0.2, 0.5), SIMD2(0.8, 0.5)], radius: 0.05, feather: 0, flow: 100)
        let coverage = BrushRasterizer.rasterize([stroke], width: 200, height: 100)
        XCTAssertEqual(value(coverage, width: 200, height: 100, at: SIMD2(0.5, 0.5)), 1, accuracy: 0.001)
        XCTAssertEqual(value(coverage, width: 200, height: 100, at: SIMD2(0.21, 0.52)), 1, accuracy: 0.001)
        XCTAssertEqual(value(coverage, width: 200, height: 100, at: SIMD2(0.5, 0.9)), 0)
        XCTAssertEqual(value(coverage, width: 200, height: 100, at: SIMD2(0.95, 0.5)), 0)
    }

    func testFlowIsEvenAlongOneStrokeAndBuildsUpAcrossStrokes() {
        let stroke = BrushStroke(points: [SIMD2(0.2, 0.5), SIMD2(0.8, 0.5)], radius: 0.05, feather: 0, flow: 50)
        let once = BrushRasterizer.rasterize([stroke], width: 200, height: 100)
        XCTAssertEqual(value(once, width: 200, height: 100, at: SIMD2(0.5, 0.5)), 0.5, accuracy: 0.001)
        XCTAssertEqual(value(once, width: 200, height: 100, at: SIMD2(0.3, 0.5)), 0.5, accuracy: 0.001)
        let twice = BrushRasterizer.rasterize([stroke, stroke], width: 200, height: 100)
        XCTAssertEqual(value(twice, width: 200, height: 100, at: SIMD2(0.5, 0.5)), 0.75, accuracy: 0.001)
    }

    func testEraseAndFeather() {
        let paint = BrushStroke(points: [SIMD2(0.5, 0.5)], radius: 0.2, feather: 0)
        let erase = BrushStroke(points: [SIMD2(0.5, 0.5)], radius: 0.05, feather: 0, erase: true)
        let coverage = BrushRasterizer.rasterize([paint, erase], width: 100, height: 100)
        XCTAssertEqual(value(coverage, width: 100, height: 100, at: SIMD2(0.5, 0.5)), 0, accuracy: 0.001)
        XCTAssertEqual(value(coverage, width: 100, height: 100, at: SIMD2(0.62, 0.5)), 1, accuracy: 0.001)

        let soft = BrushStroke(points: [SIMD2(0.5, 0.5)], radius: 0.2, feather: 100)
        let softCoverage = BrushRasterizer.rasterize([soft], width: 100, height: 100)
        let middle = value(softCoverage, width: 100, height: 100, at: SIMD2(0.6, 0.5))
        XCTAssertGreaterThan(middle, 0.2)
        XCTAssertLessThan(middle, 0.9)
    }

    func testLinearAndRadialWeights() {
        let start = SIMD2(0.5, 0.9), end = SIMD2(0.5, 0.5)
        XCTAssertEqual(MaskMath.linear(at: SIMD2(0.2, 0.95), start: start, end: end, aspect: 1.5), 1)
        XCTAssertEqual(MaskMath.linear(at: SIMD2(0.8, 0.2), start: start, end: end, aspect: 1.5), 0)
        XCTAssertEqual(MaskMath.linear(at: SIMD2(0.5, 0.7), start: start, end: end, aspect: 1.5), 0.5, accuracy: 0.001)

        let center = SIMD2(0.5, 0.5)
        let radius = SIMD2(0.3, 0.1)
        XCTAssertEqual(MaskMath.radial(at: center, center: center, radius: radius, angle: 0, feather: 50, aspect: 1), 1)
        XCTAssertGreaterThan(MaskMath.radial(at: SIMD2(0.65, 0.5), center: center, radius: radius, angle: 0, feather: 50, aspect: 1), 0.9)
        XCTAssertEqual(MaskMath.radial(at: SIMD2(0.5, 0.65), center: center, radius: radius, angle: 0, feather: 50, aspect: 1), 0)
        // Rotated by 90°, the long axis is vertical.
        XCTAssertGreaterThan(MaskMath.radial(at: SIMD2(0.5, 0.65), center: center, radius: radius, angle: 90, feather: 50, aspect: 1), 0.9)
    }

    func testCombineModes() {
        XCTAssertEqual(MaskMath.combine([(0.4, .add), (0.7, .add)]), 0.7)
        XCTAssertEqual(MaskMath.combine([(1, .add), (0.25, .subtract)]), 0.75)
        XCTAssertEqual(MaskMath.combine([(0.8, .add), (0.5, .intersect)]), 0.4)
        XCTAssertEqual(MaskMath.combine([(0.8, .subtract)]), 0)
    }

    func testMasksRoundTripAndOldFilesDecode() throws {
        var document = EditDocument()
        var mask = Mask(name: "Sky", components: [MaskCatalog.component(.sky), MaskCatalog.component(.radial, mode: .subtract)])
        mask.adjustments.exposure = -0.5
        mask.components[1].strokes = [BrushStroke(points: [SIMD2(0.1, 0.2)])]
        document.masks = [mask]
        let decoded = try EditDocument.decode(from: document.jsonData())
        XCTAssertEqual(decoded, document)

        // A mask saved before newer fields existed still loads, with defaults filled in.
        let json = """
        {"masks": [{"name": "Old", "components": [{"kind": "linear", "strokes": [{"points": [[0.5, 0.5]]}]}], "adjustments": {"exposure": 1}}],
         "beauty": {"faces": [{"anchor": {"x": 0.5, "y": 0.5, "size": 0.2}, "settings": {"smooth": 40}}]}}
        """
        let old = try EditDocument.decode(from: Data(json.utf8))
        XCTAssertEqual(old.masks.count, 1)
        XCTAssertEqual(old.masks[0].name, "Old")
        XCTAssertEqual(old.masks[0].amount, 100)
        XCTAssertEqual(old.masks[0].adjustments.exposure, 1)
        XCTAssertEqual(old.masks[0].components[0].kind, .linear)
        XCTAssertEqual(old.masks[0].components[0].mode, .add)
        XCTAssertEqual(old.masks[0].components[0].strokes[0].flow, 100)
        XCTAssertEqual(old.beauty.faces.first?.settings.smooth, 40)
        XCTAssertEqual(old.beauty.faces.first?.settings.texture, FaceRetouchSettings().texture)
    }

    func testPresetsKeepShapeMasksButDropPaintedOnes() {
        var document = EditDocument()
        var brush = Mask(name: "Brush", components: [MaskCatalog.component(.brush)])
        brush.adjustments.exposure = 1
        var sky = Mask(name: "Sky", components: [MaskCatalog.component(.sky), MaskCatalog.component(.brush, mode: .subtract)])
        sky.adjustments.exposure = -1
        document.masks = [brush, sky]
        let preset = document.adjustmentsOnly(keeping: GeometrySettings())
        XCTAssertEqual(preset.masks.count, 1)
        XCTAssertEqual(preset.masks[0].components.map(\.kind), [.sky])
    }

    func testMaskActivity() {
        var mask = Mask(components: [MaskCatalog.component(.subject)])
        XCTAssertFalse(mask.isActive, "no adjustments yet")
        mask.adjustments.colorHue = 200
        XCTAssertFalse(mask.isActive, "hue alone does nothing")
        mask.adjustments.shadows = 20
        XCTAssertTrue(mask.isActive)
        mask.isVisible = false
        XCTAssertFalse(mask.isActive)
    }
}
