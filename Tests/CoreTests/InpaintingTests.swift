import XCTest
@testable import LumoraCore

final class InpaintingTests: XCTestCase {
    private func squareHole(width: Int, height: Int, x0: Int, y0: Int, size: Int) -> [Float] {
        var hole = [Float](repeating: 0, count: width * height)
        for y in y0..<(y0 + size) {
            for x in x0..<(x0 + size) {
                hole[y * width + x] = 1
            }
        }
        return hole
    }

    func testGradientIsContinuedAndKnownPixelsKept() {
        let width = 64, height = 48
        var pixels = [SIMD3<Float>](repeating: .zero, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let v = Float(x) / Float(width - 1)
                pixels[y * width + x] = SIMD3(v, 0.5, 1 - v)
            }
        }
        var damaged = pixels
        let hole = squareHole(width: width, height: height, x0: 24, y0: 16, size: 14)
        for i in 0..<(width * height) where hole[i] > 0 {
            damaged[i] = SIMD3(1, 0, 1)
        }
        let filled = Inpainting.fill(damaged, width: width, height: height, hole: hole)
        var maxError: Float = 0
        for i in 0..<(width * height) {
            if hole[i] > 0 {
                let d = filled[i] - pixels[i]
                maxError = max(maxError, max(abs(d.x), max(abs(d.y), abs(d.z))))
            } else {
                XCTAssertEqual(filled[i], damaged[i])
            }
        }
        // Patches are copied (not interpolated), so allow a few columns of drift.
        XCTAssertLessThan(maxError, 0.12)
    }

    func testStripesContinueThroughTheHole() {
        let width = 96, height = 96
        var pixels = [SIMD3<Float>](repeating: .zero, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let on: Float = (x / 4) % 2 == 0 ? 1 : 0
                pixels[y * width + x] = SIMD3(on, on, on)
            }
        }
        let hole = squareHole(width: width, height: height, x0: 40, y0: 40, size: 18)
        var damaged = pixels
        for i in 0..<(width * height) where hole[i] > 0 {
            damaged[i] = SIMD3(0.5, 0.5, 0.5)
        }
        let filled = Inpainting.fill(damaged, width: width, height: height, hole: hole)
        // Columns are uniform: each filled pixel should match the stripe of its column
        // (up to a shift), so the fill must be close to 0 or 1, never a grey average.
        var nearBinary = 0, total = 0
        var columnConsistent = 0
        for y in 40..<58 {
            for x in 40..<58 {
                let v = filled[y * width + x].x
                total += 1
                if v < 0.2 || v > 0.8 { nearBinary += 1 }
                if abs(v - filled[40 * width + x].x) < 0.3 { columnConsistent += 1 }
            }
        }
        XCTAssertGreaterThan(Double(nearBinary) / Double(total), 0.85, "stripes stay crisp")
        XCTAssertGreaterThan(Double(columnConsistent) / Double(total), 0.85, "stripes stay vertical")
    }

    func testEmptyHoleReturnsInput() {
        let pixels = [SIMD3<Float>](repeating: SIMD3(0.2, 0.3, 0.4), count: 16 * 16)
        let filled = Inpainting.fill(pixels, width: 16, height: 16, hole: [Float](repeating: 0, count: 256))
        XCTAssertEqual(filled, pixels)
    }

    func testRetouchBoundsIncludeBrushRadius() throws {
        var operation = RetouchOperation(tool: .heal)
        operation.strokes = [BrushStroke(points: [SIMD2(0.5, 0.5)], radius: 0.1)]
        let bounds = try XCTUnwrap(operation.bounds(aspect: 2))
        XCTAssertEqual(bounds.x, 0.4, accuracy: 1e-9)
        XCTAssertEqual(bounds.width, 0.2, accuracy: 1e-9)
        // Radius is a fraction of the width: on a tall photo it covers less of the height.
        XCTAssertEqual(bounds.height, 0.1, accuracy: 1e-9)
    }
}
