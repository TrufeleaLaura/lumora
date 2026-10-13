import XCTest
@testable import LumoraCore

final class LiquifyTests: XCTestCase {
    func testPushDragsContentAlong() throws {
        let stroke = LiquifyStroke(tool: .push, points: [SIMD2(0.4, 0.5), SIMD2(0.5, 0.5)], radius: 0.1, strength: 100)
        let field = try XCTUnwrap(LiquifyMath.field([stroke], aspect: 1))
        // Where the finger ended, the photo shows what was under it before: sample to the left.
        let offset = field.offset(atX: 0.5, y: 0.5)
        XCTAssertLessThan(offset.x, -0.03)
        XCTAssertEqual(offset.y, 0, accuracy: 0.005)
        // Far away nothing moves.
        let far = field.offset(atX: 0.9, y: 0.9)
        XCTAssertEqual(far.x, 0, accuracy: 1e-6)
    }

    func testBloatAndPinchSampleTowardAndAwayFromTheCenter() throws {
        let bloat = try XCTUnwrap(LiquifyMath.field([LiquifyStroke(tool: .bloat, points: [SIMD2(0.5, 0.5)], radius: 0.2, strength: 100)], aspect: 1))
        // Right of the center, an enlarged view samples closer to the center (negative x offset).
        XCTAssertLessThan(bloat.offset(atX: 0.58, y: 0.5).x, -0.002)
        let pinch = try XCTUnwrap(LiquifyMath.field([LiquifyStroke(tool: .pinch, points: [SIMD2(0.5, 0.5)], radius: 0.2, strength: 100)], aspect: 1))
        XCTAssertGreaterThan(pinch.offset(atX: 0.58, y: 0.5).x, 0.002)
    }

    func testRestoreUndoesPartOfAPush() throws {
        let push = LiquifyStroke(tool: .push, points: [SIMD2(0.4, 0.5), SIMD2(0.5, 0.5)], radius: 0.1, strength: 100)
        let restore = LiquifyStroke(tool: .restore, points: [SIMD2(0.5, 0.5)], radius: 0.15, strength: 100)
        let pushed = try XCTUnwrap(LiquifyMath.field([push], aspect: 1)).offset(atX: 0.5, y: 0.5)
        let restored = LiquifyMath.field([push, restore], aspect: 1)?.offset(atX: 0.5, y: 0.5) ?? .zero
        XCTAssertLessThan(abs(restored.x), abs(pushed.x) * 0.6)
    }

    func testNoStrokesNoField() {
        XCTAssertNil(LiquifyMath.field([], aspect: 1.5))
    }
}
