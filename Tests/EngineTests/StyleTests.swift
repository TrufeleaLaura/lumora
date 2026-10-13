import CoreImage
import LumoraCore
import XCTest
@testable import LumoraEngine

final class StyleTests: XCTestCase {
    private let pipeline = RenderPipeline()
    private static let scene = TestScene.image()
    private static let sceneAnalysis = ImageAnalysis(image: scene)
    private static let portrait = Fixtures.photo("portrait-woman")
    private static let portraitAnalysis = Fixtures.analysis("portrait-woman", image: portrait)

    private func render(_ image: CIImage, _ analysis: ImageAnalysis, _ change: (inout CreativeSettings) -> Void) -> CIImage {
        var document = EditDocument()
        change(&document.styles)
        return pipeline.apply(document, to: image, analysis: analysis)
    }

    private func detail(_ image: CIImage, _ rect: CGRect) -> Float {
        ImageStats.noiseLevel(of: image.cropped(to: rect))
    }

    func testHDRLiftsShadowsAndAddsDetail() {
        let output = render(Self.scene, Self.sceneAnalysis) { $0.hdr = 100 }
        let shadowBefore = ImageStats.averageLuminance(of: Self.scene.cropped(to: TestScene.shadowRect))
        let shadowAfter = ImageStats.averageLuminance(of: output.cropped(to: TestScene.shadowRect))
        XCTAssertGreaterThan(shadowAfter, shadowBefore * 1.3, "shadows open up")
        XCTAssertGreaterThan(detail(output, TestScene.mountainRect), detail(Self.scene, TestScene.mountainRect), "more local detail")
    }

    func testNoirIsBlackAndWhite() {
        let output = render(Self.scene, Self.sceneAnalysis) { $0.noir = 80 }
        let color = ImageStats.averageColor(of: output.cropped(to: TestScene.patchRect(0)))
        XCTAssertEqual(color.x, color.y, accuracy: 0.01)
        XCTAssertEqual(color.y, color.z, accuracy: 0.01)
    }

    func testLensBlurKeepsTheFocusAreaSharp() {
        let output = render(Self.scene, Self.sceneAnalysis) { styles in
            styles.lensBlur.amount = 100
            styles.lensBlur.mode = .radial
            styles.lensBlur.center = SIMD2(400.0 / 960, 150.0 / 640)
            styles.lensBlur.size = 0.12
            styles.lensBlur.transition = 20
        }
        let inFocus = CGRect(x: 380, y: 130, width: 40, height: 40)
        let farAway = CGRect(x: 820, y: 120, width: 60, height: 50)
        XCTAssertGreaterThan(detail(output, inFocus), detail(Self.scene, inFocus) * 0.85)
        XCTAssertLessThan(detail(output, farAway), detail(Self.scene, farAway) * 0.5)
    }

    func testTiltShiftBand() {
        var settings = LensBlurSettings()
        settings.mode = .band
        settings.center = SIMD2(0.5, 0.25)
        settings.size = 0.1
        settings.transition = 10
        let mask = pipeline.focusMask(settings, extent: Self.scene.extent, analysis: Self.sceneAnalysis)
        XCTAssertGreaterThan(ImageStats.averageColor(of: mask.cropped(to: CGRect(x: 100, y: 150, width: 700, height: 10))).x, 0.99)
        XCTAssertLessThan(ImageStats.averageColor(of: mask.cropped(to: CGRect(x: 100, y: 500, width: 700, height: 40))).x, 0.01)
    }

    func testRGBSplitOnlyChangesEdges() {
        let output = render(Self.scene, Self.sceneAnalysis) { $0.rgbSplit = 100 }
        // Inside a flat patch nothing moves; at the boundary between two patches the channels separate.
        let inside = TestScene.patchRect(1).insetBy(dx: 20, dy: 5)
        let a = ImageStats.averageColor(of: output.cropped(to: inside))
        let b = ImageStats.averageColor(of: Self.scene.cropped(to: inside))
        XCTAssertEqual(a.x, b.x, accuracy: 0.01)
        let boundaryX = CGFloat(TestScene.width) / CGFloat(TestImages.patchColors.count)
        let edge = CGRect(x: boundaryX - 3, y: 20, width: 6, height: 30)
        let edgeOut = ImageStats.averageColor(of: output.cropped(to: edge))
        let edgeIn = ImageStats.averageColor(of: Self.scene.cropped(to: edge))
        XCTAssertGreaterThan(abs(edgeOut.x - edgeIn.x) + abs(edgeOut.z - edgeIn.z), 0.01)
    }

    func testWriteStyleSheets() throws {
        let scene = Self.scene
        let sa = Self.sceneAnalysis
        try ContactSheet.write([
            ("Scene", scene),
            ("HDR Scape 80", render(scene, sa) { $0.hdr = 80 }),
            ("Drama 70", render(scene, sa) { $0.drama = 70 }),
            ("Tonal contrast", render(scene, sa) { $0.tonalHigh = 60; $0.tonalMid = 60; $0.tonalLow = 60 }),
            ("Glamour glow 70", render(scene, sa) { $0.glow = 70; $0.glowWarmth = 30 }),
            ("Halation 80", render(scene, sa) { $0.halation = 80 }),
            ("Vintage 80", render(scene, sa) { $0.vintage = 80 }),
            ("Noir 80", render(scene, sa) { $0.noir = 80 }),
            ("Grunge 70", render(scene, sa) { $0.grunge = 70 }),
            ("Grunge 70 style 3", render(scene, sa) { $0.grunge = 70; $0.grungeStyle = 3 }),
            ("RGB split 80", render(scene, sa) { $0.rgbSplit = 80 }),
            ("Tilt-shift + miniature", render(scene, sa) { styles in
                styles.lensBlur.amount = 80
                styles.lensBlur.mode = .band
                styles.lensBlur.center = SIMD2(0.5, 0.3)
                styles.lensBlur.size = 0.15
                styles.lensBlur.miniature = 70
            }),
        ], name: "60-styles-scene", columns: 4)

        let portrait = Self.portrait
        let pa = Self.portraitAnalysis
        try ContactSheet.write([
            ("Portrait", portrait),
            ("Lens blur: subject", render(portrait, pa) { $0.lensBlur.amount = 90; $0.lensBlur.bokeh = 70 }),
            ("Lens blur: radial", render(portrait, pa) { styles in
                styles.lensBlur.amount = 80
                styles.lensBlur.mode = .radial
                styles.lensBlur.center = SIMD2(0.5, 0.6)
                styles.lensBlur.size = 0.2
            }),
            ("Drama 60, saturation -60", render(portrait, pa) { $0.drama = 60; $0.dramaSaturation = -60 }),
            ("Glamour glow 80", render(portrait, pa) { $0.glow = 80 }),
            ("Vintage 70 + halation 50", render(portrait, pa) { $0.vintage = 70; $0.halation = 50 }),
            ("Noir 70", render(portrait, pa) { $0.noir = 70 }),
            ("HDR Scape 60", render(portrait, pa) { $0.hdr = 60 }),
        ], name: "61-styles-portrait", columns: 4)
    }
}
