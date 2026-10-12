import CoreImage
import LumoraCore
import XCTest
@testable import LumoraEngine

/// Checks that photos decoded from files keep their colors through the pipeline, and
/// records how Core Image's generator images compare (see contact sheet 01).
final class ColorManagementTests: XCTestCase {
    private let pipeline = RenderPipeline()

    private var patchRects: [CGRect] {
        (0..<9).map { CGRect(x: CGFloat($0) * 80 + 20, y: 300, width: 40, height: 40) }
    }

    /// Nearly-identity edit that still runs every stage of the pipeline.
    private var nearIdentity: EditDocument {
        var document = EditDocument()
        document.light.exposure = 0.0001
        document.color.vibrance = 0.0001
        document.color.temperature = 0.0001
        return document
    }

    func testFileDecodedPhotoKeepsColorsThroughPipeline() throws {
        let photo = try XCTUnwrap(TestImages.fileDecodedChart())
        let processed = pipeline.apply(nearIdentity, to: photo)
        for rect in patchRects {
            let a = ImageStats.averageColor(of: photo.cropped(to: rect))
            let b = ImageStats.averageColor(of: processed.cropped(to: rect))
            XCTAssertEqual(a.x, b.x, accuracy: 0.01, "red at \(rect)")
            XCTAssertEqual(a.y, b.y, accuracy: 0.01, "green at \(rect)")
            XCTAssertEqual(a.z, b.z, accuracy: 0.01, "blue at \(rect)")
        }
    }

    func testFileRoundTripPreservesSRGBValues() throws {
        // A patch written as sRGB (0.8, 0.15, 0.15) must read back as the same sRGB values.
        let photo = try XCTUnwrap(TestImages.fileDecodedChart())
        let patch = photo.cropped(to: patchRects[0])
        let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: patch, kCIInputExtentKey: CIVector(cgRect: patch.extent)])!
        var pixel = [UInt8](repeating: 0, count: 4)
        RenderContext.shared.render(filter.outputImage!, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: patch.extent.minX, y: patch.extent.minY, width: 1, height: 1), format: .RGBA8, colorSpace: RenderContext.sRGB)
        XCTAssertEqual(Double(pixel[0]) / 255, 0.80, accuracy: 0.02)
        XCTAssertEqual(Double(pixel[1]) / 255, 0.15, accuracy: 0.02)
    }

    func testWriteColorComparisonSheet() throws {
        let generated = TestImages.colorChart()
        let photo = try XCTUnwrap(TestImages.fileDecodedChart())
        try ContactSheet.write([
            ("Generator: original", generated),
            ("Generator: pipeline", pipeline.apply(nearIdentity, to: generated)),
            ("File: original", photo),
            ("File: pipeline", pipeline.apply(nearIdentity, to: photo)),
        ], name: "01-color-management", columns: 2)
    }
}
