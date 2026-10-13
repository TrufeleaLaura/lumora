import XCTest
@testable import LumoraCore

final class WarpTests: XCTestCase {
    func testIdentityControlsGiveIdentity() {
        let points = [SIMD2(0.2, 0.2), SIMD2(0.8, 0.3), SIMD2(0.5, 0.9), SIMD2(0.1, 0.7)]
        for v in [SIMD2(0.4, 0.4), SIMD2(0.7, 0.6), SIMD2(0.05, 0.95)] {
            let mapped = MovingLeastSquares.rigid(v, from: points, to: points)
            XCTAssertEqual(mapped.x, v.x, accuracy: 1e-9)
            XCTAssertEqual(mapped.y, v.y, accuracy: 1e-9)
        }
    }

    func testControlPointsMapExactly() {
        let from = [SIMD2(0.2, 0.2), SIMD2(0.8, 0.2), SIMD2(0.5, 0.8)]
        let to = [SIMD2(0.25, 0.2), SIMD2(0.75, 0.2), SIMD2(0.5, 0.9)]
        for (p, q) in zip(from, to) {
            let mapped = MovingLeastSquares.rigid(p, from: from, to: to)
            XCTAssertEqual(mapped.x, q.x, accuracy: 1e-9)
            XCTAssertEqual(mapped.y, q.y, accuracy: 1e-9)
        }
    }

    func testPureTranslationIsReproduced() {
        let from = [SIMD2(0.2, 0.2), SIMD2(0.8, 0.2), SIMD2(0.5, 0.8), SIMD2(0.3, 0.6)]
        let shift = SIMD2(0.05, -0.02)
        let to = from.map { $0 + shift }
        let mapped = MovingLeastSquares.rigid(SIMD2(0.45, 0.4), from: from, to: to)
        XCTAssertEqual(mapped.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(mapped.y, 0.38, accuracy: 1e-9)
    }

    func testRotationIsReproduced() {
        let from = [SIMD2(1.0, 0.0), SIMD2(0.0, 1.0), SIMD2(-1.0, 0.0), SIMD2(0.0, -1.0)]
        let angle = Double.pi / 6
        let rotate: (SIMD2<Double>) -> SIMD2<Double> = { SIMD2($0.x * cos(angle) - $0.y * sin(angle), $0.x * sin(angle) + $0.y * cos(angle)) }
        let to = from.map(rotate)
        let v = SIMD2(0.3, 0.2)
        let mapped = MovingLeastSquares.rigid(v, from: from, to: to)
        let expected = rotate(v)
        XCTAssertEqual(mapped.x, expected.x, accuracy: 1e-9)
        XCTAssertEqual(mapped.y, expected.y, accuracy: 1e-9)
    }

    func testFieldIsZeroAtBorderAndMovesTheControl() {
        let region = CGRectValue(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        // Pull the center point 0.03 to the right (aspect 1).
        let control = WarpControl(source: SIMD2(0.5, 0.5), target: SIMD2(0.53, 0.5))
        let field = DisplacementField.build(controls: [control], region: region, aspect: 1, columns: 33, rows: 33)
        XCTAssertFalse(field.isEmpty)
        // Backward map: the output point at the target samples the original source.
        let atTarget = field.offset(atX: 0.53, y: 0.5)
        XCTAssertEqual(atTarget.x, -0.03, accuracy: 0.004)
        XCTAssertEqual(atTarget.y, 0, accuracy: 0.004)
        // Border and outside stay still.
        XCTAssertEqual(field.offset(atX: 0.3, y: 0.5).x, 0, accuracy: 1e-6)
        XCTAssertEqual(field.offset(atX: 0.1, y: 0.1), SIMD2(0, 0))
    }

    func testAspectIsRespected() {
        // A 2:1 tall image (aspect 2): moving up by 0.02 width-units is 0.01 in normalized y.
        let region = CGRectValue(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        let control = WarpControl(source: SIMD2(0.5, 1.0), target: SIMD2(0.5, 1.02))
        let field = DisplacementField.build(controls: [control], region: region, aspect: 2, columns: 41, rows: 41)
        let offset = field.offset(atX: 0.5, y: 0.51)
        XCTAssertEqual(offset.y, -0.01, accuracy: 0.0015)
    }

    func testRectExpansion() {
        let rect = CGRectValue(x: 0.4, y: 0.4, width: 0.2, height: 0.1).expanded(by: 2)
        XCTAssertEqual(rect.width, 0.4, accuracy: 1e-9)
        XCTAssertEqual(rect.midY, 0.45, accuracy: 1e-9)
        let clamped = CGRectValue(x: 0.9, y: 0.0, width: 0.1, height: 0.1).expanded(by: 4)
        XCTAssertEqual(clamped.x + clamped.width, 1, accuracy: 1e-9)
        XCTAssertEqual(clamped.y, 0, accuracy: 1e-9)
    }
}
