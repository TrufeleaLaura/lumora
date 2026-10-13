import CoreImage
import LumoraCore
import XCTest
@testable import LumoraEngine

final class OverlayTests: XCTestCase {
    private let pipeline = RenderPipeline()
    private static let scene = TestScene.image()
    private static let sceneAnalysis = ImageAnalysis(image: scene)
    private static let portrait = Fixtures.photo("portrait-smile")
    private static let portraitAnalysis = ImageAnalysis(image: portrait)

    private func render(_ image: CIImage, _ analysis: ImageAnalysis, _ change: (inout EditDocument) -> Void) -> CIImage {
        var document = EditDocument()
        change(&document)
        return pipeline.apply(document, to: image, analysis: analysis)
    }

    private func luminance(_ image: CIImage, _ rect: CGRect) -> Float {
        ImageStats.averageLuminance(of: image.cropped(to: rect))
    }

    func testFramesChangeTheOutputSize() {
        let border = render(Self.scene, Self.sceneAnalysis) { $0.frame.style = .border; $0.frame.width = 50 }
        let b = 640.0 * 0.1 * 0.5
        XCTAssertEqual(Double(border.extent.width), 960 + 2 * b, accuracy: 0.5)
        XCTAssertEqual(Double(border.extent.height), 640 + 2 * b, accuracy: 0.5)
        // The border is white, the photo is inside it.
        XCTAssertGreaterThan(luminance(border, CGRect(x: 2, y: 2, width: 20, height: 20)), 0.95)

        let instant = render(Self.scene, Self.sceneAnalysis) { $0.frame.style = .polaroid }
        let layout = FrameLayout.layout(FrameSettings.withStyle(.polaroid), contentWidth: 960, contentHeight: 640)
        XCTAssertEqual(Double(instant.extent.height), layout.height, accuracy: 0.5)
        XCTAssertGreaterThan(layout.content.y, (layout.height - layout.content.y - layout.content.height) * 2, "thick bottom edge")

        for style in [FrameStyle.film, .super8, .vhs] {
            let framed = render(Self.scene, Self.sceneAnalysis) { $0.frame.style = style }
            let expected = FrameLayout.layout(FrameSettings.withStyle(style), contentWidth: 960, contentHeight: 640)
            XCTAssertEqual(Double(framed.extent.width), expected.width, accuracy: 0.5, "\(style)")
            XCTAssertTrue(framed.extent.width.isFinite)
        }
    }

    func testTextAndStickersAppearWhereTheyArePlaced() {
        let dark = TestScene.shadowRect
        let position = SIMD2(Double(dark.midX) / 960, Double(dark.midY) / 640)
        let withText = render(Self.scene, Self.sceneAnalysis) { document in
            var layer = TextLayer(text: "LUMORA")
            layer.font = .sans
            layer.size = 0.05
            layer.position = position
            document.texts = [layer]
        }
        XCTAssertGreaterThan(luminance(withText, dark), luminance(Self.scene, dark) + 0.02, "white text on the dark area")
        XCTAssertEqual(luminance(withText, TestScene.sunRect), luminance(Self.scene, TestScene.sunRect), accuracy: 1e-4)

        let withSticker = render(Self.scene, Self.sceneAnalysis) { document in
            var layer = TextLayer(symbol: "heart.fill")
            layer.size = 0.08
            layer.color = RGBColor(1, 0.2, 0.3)
            layer.position = position
            document.texts = [layer]
        }
        let color = ImageStats.averageColor(of: withSticker.cropped(to: dark.insetBy(dx: 40, dy: 15)))
        XCTAssertGreaterThan(color.x, color.y * 2, "a red heart")
    }

    func testLightLeakBrightensItsCorner() {
        let output = render(Self.scene, Self.sceneAnalysis) { $0.overlays.lightLeak = 100; $0.overlays.lightLeakStyle = 0 }
        let corner = CGRect(x: 10, y: 560, width: 60, height: 60)
        let opposite = CGRect(x: 880, y: 70, width: 60, height: 40)
        XCTAssertGreaterThan(luminance(output, corner) - luminance(Self.scene, corner), 0.05)
        XCTAssertLessThan(abs(luminance(output, opposite) - luminance(Self.scene, opposite)), 0.01)
    }

    func testDateStampIsOrange() {
        let output = render(Self.scene, Self.sceneAnalysis) { $0.frame.dateStamp = true; $0.frame.dateText = "'26 10 13" }
        XCTAssertEqual(output.extent, Self.scene.extent)
        let corner = CGRect(x: 960 - 640 * 0.05 - 150, y: 640 * 0.05, width: 150, height: 40)
        let before = ImageStats.averageColor(of: Self.scene.cropped(to: corner))
        let after = ImageStats.averageColor(of: output.cropped(to: corner))
        XCTAssertGreaterThan(after.x - before.x, 0.03, "more red")
        XCTAssertGreaterThan(after.x - after.z, before.x - before.z, "orange, not white")
        XCTAssertEqual(RenderPipeline.stampText(for: Date(timeIntervalSince1970: 1_791_849_600)).count, 9)
    }

    // MARK: - Contact sheets

    func testWriteOverlaySheets() throws {
        let scene = Self.scene
        let sa = Self.sceneAnalysis
        try ContactSheet.write([
            ("Scene", scene),
            ("Dust 100", render(scene, sa) { $0.overlays.dust = 100 }),
            ("Scratches 100", render(scene, sa) { $0.overlays.scratches = 100 }),
            ("Light leak 80", render(scene, sa) { $0.overlays.lightLeak = 80 }),
            ("Light leak style 4", render(scene, sa) { $0.overlays.lightLeak = 80; $0.overlays.lightLeakStyle = 4 }),
            ("Paper 80", render(scene, sa) { $0.overlays.paper = 80 }),
            ("Plastic 80", render(scene, sa) { $0.overlays.plastic = 80 }),
            ("Blinds 70", render(scene, sa) { $0.overlays.shadows = 70 }),
            ("Window 70", render(scene, sa) { $0.overlays.shadows = 70; $0.overlays.shadowStyle = 2 }),
            ("Leaves 70", render(scene, sa) { $0.overlays.shadows = 70; $0.overlays.shadowStyle = 3 }),
            ("Prism 80", render(scene, sa) { $0.overlays.prism = 80 }),
            ("Grunge style 3", render(scene, sa) { $0.styles.grunge = 70; $0.styles.grungeStyle = 3 }),
        ], name: "70-overlays", columns: 4)

        let portrait = Self.portrait
        let pa = Self.portraitAnalysis
        try ContactSheet.write([
            ("Border", render(portrait, pa) { $0.frame.style = .border }),
            ("Instant + date", render(portrait, pa) { $0.frame.style = .polaroid; $0.frame.dateStamp = true; $0.frame.dateText = "'26 10 13" }),
            ("35 mm", render(portrait, pa) { $0.frame.style = .film }),
            ("Super 8", render(portrait, pa) { $0.frame.style = .super8 }),
            ("VHS + date", render(portrait, pa) { $0.frame.style = .vhs; $0.frame.dateStamp = true; $0.frame.dateText = "OCT 13 2026" }),
            ("Text & stickers", render(portrait, pa) { document in
                var title = TextLayer(text: "golden hour")
                title.font = .script
                title.size = 0.1
                title.position = SIMD2(0.5, 0.82)
                title.shadow = true
                var caption = TextLayer(text: "SUMMER '26")
                caption.font = .futura
                caption.size = 0.045
                caption.spacing = 60
                caption.position = SIMD2(0.5, 0.12)
                caption.color = .cream
                var heart = TextLayer(symbol: "heart.fill")
                heart.size = 0.07
                heart.color = RGBColor(0.95, 0.35, 0.45)
                heart.position = SIMD2(0.82, 0.3)
                heart.rotation = -15
                var sparkle = TextLayer(symbol: "sparkles")
                sparkle.size = 0.06
                sparkle.position = SIMD2(0.18, 0.62)
                document.texts = [title, caption, heart, sparkle]
            }),
        ], name: "71-frames-text", columns: 3)
    }
}

extension FrameSettings {
    static func withStyle(_ style: FrameStyle) -> FrameSettings {
        var settings = FrameSettings()
        settings.style = style
        return settings
    }
}
