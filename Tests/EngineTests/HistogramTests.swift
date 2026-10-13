import CoreImage
import LumoraCore
import XCTest
@testable import LumoraEngine

final class HistogramTests: XCTestCase {
    func testHistogramFindsDarkAndBrightAreas() {
        let scene = TestScene.image()
        let data = Histogram.compute(scene)
        XCTAssertEqual(data.luma.count, 64)
        XCTAssertEqual(data.luma.max(), 1)
        // The scene has deep shadows and a bright sky: both ends of the curve are populated.
        XCTAssertGreaterThan(data.luma[2..<10].reduce(0, +), 0.05)
        XCTAssertGreaterThan(data.luma[44..<62].reduce(0, +), 0.3)

        var document = EditDocument()
        document.light.exposure = 3
        let blown = Histogram.compute(RenderPipeline().apply(document, to: scene))
        XCTAssertGreaterThan(blown.highlightClip, 0.2)
    }

    func testWhiteBalancePickerNeutralizesAWarmGrey() {
        // A grey card under warm light.
        let warmGrey = SIMD3(0.40, 0.36, 0.30)
        let result = RenderPipeline().neutralizingWhiteBalance(for: warmGrey)
        XCTAssertLessThan(result.temperature, -10)
        var settings = ColorSettings()
        settings.temperature = result.temperature
        settings.tint = result.tint
        let floats: [Float] = [0.40, 0.36, 0.30, 1]
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let pixel = CIImage(bitmapData: data, bytesPerRow: 16, size: CGSize(width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        let read = RenderContext.readFloats(RenderPipeline().applyWhiteBalance(settings, to: pixel).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)))
        let lab = ColorMath.linearSRGBToOklab(Double(read.pixels[0]), Double(read.pixels[1]), Double(read.pixels[2]))
        XCTAssertLessThan((lab.1 * lab.1 + lab.2 * lab.2).squareRoot(), 0.02, "close to neutral")
    }
}
