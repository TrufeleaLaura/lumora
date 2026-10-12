import CoreImage
import LumoraCore
import XCTest
@testable import LumoraEngine

final class RenderPipelineTests: XCTestCase {
    private let pipeline = RenderPipeline()
    /// Decoded from a PNG file, like a real photo.
    private let chart = TestImages.fileDecodedChart()!

    private func render(_ change: (inout EditDocument) -> Void) -> CIImage {
        var document = EditDocument()
        change(&document)
        return pipeline.apply(document, to: chart)
    }

    func testMetalKernelLibraryLoads() {
        XCTAssertFalse(Kernels.library.isEmpty)
        _ = Kernels.basicTone
    }

    func testIdentityDocumentLeavesImageUntouched() {
        let output = pipeline.apply(EditDocument(), to: chart)
        XCTAssertTrue(output === chart)
    }

    func testExposureBrightensAndDarkens() {
        let base = ImageStats.averageLuminance(of: chart)
        let brighter = ImageStats.averageLuminance(of: render { $0.light.exposure = 1 })
        let darker = ImageStats.averageLuminance(of: render { $0.light.exposure = -1 })
        XCTAssertGreaterThan(brighter, base * 1.5)
        XCTAssertLessThan(darker, base * 0.75)
    }

    func testWarmTemperatureShiftsTowardRed() {
        let base = ImageStats.averageColor(of: chart)
        let warm = ImageStats.averageColor(of: render { $0.color.temperature = 60 })
        let cool = ImageStats.averageColor(of: render { $0.color.temperature = -60 })
        XCTAssertGreaterThan(warm.x - warm.z, base.x - base.z)
        XCTAssertLessThan(cool.x - cool.z, base.x - base.z)
    }

    func testPositiveTintShiftsTowardMagenta() {
        let base = ImageStats.averageColor(of: chart)
        let magenta = ImageStats.averageColor(of: render { $0.color.tint = 60 })
        let baseGreenBias = base.y - (base.x + base.z) / 2
        let tintedGreenBias = magenta.y - (magenta.x + magenta.z) / 2
        XCTAssertLessThan(tintedGreenBias, baseGreenBias)
    }

    func testSaturationMinus100IsMonochrome() {
        let grey = render { $0.color.saturation = -100 }
        let red = grey.cropped(to: CGRect(x: 10, y: 300, width: 40, height: 40))
        let c = ImageStats.averageColor(of: red)
        XCTAssertEqual(c.x, c.y, accuracy: 0.01)
        XCTAssertEqual(c.y, c.z, accuracy: 0.01)
    }

    func testContrastIncreasesSpread() {
        let dark = CGRect(x: 60, y: 20, width: 40, height: 40)
        let bright = CGRect(x: 620, y: 20, width: 40, height: 40)
        func spread(_ image: CIImage) -> Float {
            ImageStats.averageLuminance(of: image.cropped(to: bright)) - ImageStats.averageLuminance(of: image.cropped(to: dark))
        }
        XCTAssertGreaterThan(spread(render { $0.light.contrast = 60 }), spread(chart))
        XCTAssertLessThan(spread(render { $0.light.contrast = -60 }), spread(chart))
    }

    func testExportEncodesJPEG() throws {
        let data = try Exporter.encode(render { $0.light.exposure = 0.3 }, format: .jpeg)
        XCTAssertGreaterThan(data.count, 1000)
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
    }

    func testFileDecodedPhotoLoadsAsImageSource() throws {
        let data = try XCTUnwrap(TestImages.chartPNG(width: 720, height: 480))
        let source = try XCTUnwrap(ImageSource(data: data))
        XCTAssertEqual(source.pixelSize, CGSize(width: 720, height: 480))
        XCTAssertEqual(source.preferredFileExtension, "png")
        XCTAssertFalse(source.isRAW)
        let proxy = source.makeProxy(maxDimension: 360)
        XCTAssertEqual(proxy.extent.width, 360)
        XCTAssertEqual(proxy.extent.height, 240)
    }

    /// Visual review sheet uploaded by CI.
    func testWriteContactSheet() throws {
        let items: [(String, CIImage)] = [
            ("Original", chart),
            ("Exposure +1", render { $0.light.exposure = 1 }),
            ("Exposure -1", render { $0.light.exposure = -1 }),
            ("Contrast +60", render { $0.light.contrast = 60 }),
            ("Contrast -60", render { $0.light.contrast = -60 }),
            ("Whites +80", render { $0.light.whites = 80 }),
            ("Blacks +80", render { $0.light.blacks = 80 }),
            ("Blacks -80", render { $0.light.blacks = -80 }),
            ("Temp +60", render { $0.color.temperature = 60 }),
            ("Temp -60", render { $0.color.temperature = -60 }),
            ("Tint +60", render { $0.color.tint = 60 }),
            ("Vibrance +80", render { $0.color.vibrance = 80 }),
            ("Saturation +60", render { $0.color.saturation = 60 }),
            ("Saturation -100", render { $0.color.saturation = -100 }),
        ]
        let url = try ContactSheet.write(items, name: "00-basic-adjustments")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
