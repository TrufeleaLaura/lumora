import CoreImage
import LumoraCore
import XCTest
@testable import LumoraEngine

final class GeometryTests: XCTestCase {
    private let scene = TestScene.image() // 960 x 640
    private let pipeline = RenderPipeline()

    private func render(_ change: (inout GeometrySettings) -> Void, includeCrop: Bool = true) -> CIImage {
        var document = EditDocument()
        change(&document.geometry)
        return pipeline.apply(document, to: scene, includeCrop: includeCrop)
    }

    private func isOpaque(_ image: CIImage, _ rect: CGRect) -> Bool {
        ImageStats.averageColor(of: image.cropped(to: rect)).w > 0.99
    }

    func testQuarterTurnSwapsDimensions() {
        let turned = render { $0.quarterTurns = 1 }
        XCTAssertEqual(turned.extent, CGRect(x: 0, y: 0, width: 640, height: 960))
        // Sky (top of the photo) is on the right after a clockwise turn.
        let right = ImageStats.averageColor(of: turned.cropped(to: CGRect(x: 600, y: 400, width: 30, height: 100)))
        XCTAssertGreaterThan(right.z, right.y * 0.95) // bluish sky
        XCTAssertEqual(render { $0.quarterTurns = 2 }.extent.size, CGSize(width: 960, height: 640))
    }

    func testFlipMirrorsContent() {
        let flipped = render { $0.flipHorizontal = true }
        let sunOriginal = ImageStats.averageLuminance(of: scene.cropped(to: TestScene.sunRect))
        let mirroredSun = TestScene.sunRect.applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -960, y: 0))
        XCTAssertEqual(ImageStats.averageLuminance(of: flipped.cropped(to: mirroredSun)), sunOriginal, accuracy: 0.02)
    }

    func testCropProducesExpectedSize() {
        let cropped = render { $0.crop = CropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5) }
        XCTAssertEqual(cropped.extent, CGRect(x: 0, y: 0, width: 480, height: 320))
        let uncropped = render({ $0.crop = CropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5) }, includeCrop: false)
        XCTAssertEqual(uncropped.extent.size, CGSize(width: 960, height: 640))
    }

    func testStraightenAndPerspectiveLeaveNoEmptyCorners() {
        let cases: [(String, (inout GeometrySettings) -> Void)] = [
            ("straighten +12", { $0.straighten = 12 }),
            ("straighten -30", { $0.straighten = -30 }),
            ("vertical +100", { $0.vertical = 100 }),
            ("vertical -100", { $0.vertical = -100 }),
            ("horizontal +80", { $0.horizontal = 80 }),
        ]
        for (name, change) in cases {
            let image = render(change)
            XCTAssertEqual(image.extent.size, CGSize(width: 960, height: 640), name)
            for corner in [CGRect(x: 0, y: 0, width: 6, height: 6), CGRect(x: 954, y: 634, width: 6, height: 6), CGRect(x: 0, y: 634, width: 6, height: 6), CGRect(x: 954, y: 0, width: 6, height: 6)] {
                XCTAssertTrue(isOpaque(image, corner), "\(name) corner \(corner)")
            }
        }
    }

    func testVignetteFollowsCrop() {
        var document = EditDocument()
        document.geometry.crop = CropRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        document.effects.vignette = -100
        let image = pipeline.apply(document, to: scene)
        XCTAssertEqual(image.extent.size, CGSize(width: 480, height: 320))
        let corner = ImageStats.averageLuminance(of: image.cropped(to: CGRect(x: 0, y: 300, width: 20, height: 20)))
        let reference = ImageStats.averageLuminance(of: scene.cropped(to: CGRect(x: 0, y: 620, width: 20, height: 20)))
        XCTAssertLessThan(corner, reference * 0.8)
    }

    func testWriteGeometrySheet() throws {
        try ContactSheet.write([
            ("Original", scene),
            ("Rotate 90°", render { $0.quarterTurns = 1 }),
            ("Flip horizontal", render { $0.flipHorizontal = true }),
            ("Straighten +8°", render { $0.straighten = 8 }),
            ("Vertical +80", render { $0.vertical = 80 }),
            ("Horizontal -80", render { $0.horizontal = -80 }),
            ("Crop 4:5", render {
                $0.aspect = .portrait4x5
                $0.crop = GeometryMath.crop(aspect: 0.8, imageWidth: 960, imageHeight: 640)
            }),
            ("Crop 16:9 + 3°", render {
                $0.straighten = 3
                $0.crop = GeometryMath.crop(aspect: 16.0 / 9.0, imageWidth: 960, imageHeight: 640)
            }),
        ], name: "07-geometry")
    }
}
