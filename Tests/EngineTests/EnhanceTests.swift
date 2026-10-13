import CoreImage
import LumoraCore
import XCTest
@testable import LumoraEngine

final class EnhanceTests: XCTestCase {
    private let pipeline = RenderPipeline()
    private static let scene = TestScene.image()
    private static let sceneAnalysis = ImageAnalysis(image: scene)
    private static let body = Fixtures.photo("body-front")
    private static let bodyAnalysis = Fixtures.analysis("body-front", image: body)

    /// The scene one stop too dark with a warm cast.
    private static let dullScene: CIImage = {
        var document = EditDocument()
        document.light.exposure = -1.2
        document.color.temperature = 45
        return RenderPipeline().apply(document, to: scene)
    }()

    func testAutoEnhanceFixesExposureAndColorCast() {
        let proposal = AutoEnhance.propose(for: Self.dullScene)
        XCTAssertGreaterThan(proposal.light.exposure, 0.3, "brightens the dark photo")
        XCTAssertLessThan(proposal.temperature, -5, "cools the warm cast")
        // Applying it brings the photo closer to the original.
        var document = EditDocument()
        proposal.apply(to: &document)
        let fixed = pipeline.apply(document, to: Self.dullScene, analysis: ImageAnalysis(image: Self.dullScene))
        let original = ImageStats.averageLuminance(of: Self.scene)
        XCTAssertLessThan(abs(ImageStats.averageLuminance(of: fixed) - original), abs(ImageStats.averageLuminance(of: Self.dullScene) - original))
    }

    func testAutoEnhanceLeavesAGoodPhotoMostlyAlone() {
        let proposal = AutoEnhance.propose(for: Self.scene)
        XCTAssertLessThan(abs(proposal.light.exposure), 0.6)
        XCTAssertLessThan(abs(proposal.temperature), 25)
    }

    func testSkyReplacementChangesOnlyTheSky() {
        var document = EditDocument()
        document.sky.style = .sunset
        document.sky.relight = 0
        let output = pipeline.apply(document, to: Self.scene, analysis: Self.sceneAnalysis)
        let skyBefore = ImageStats.averageColor(of: Self.scene.cropped(to: TestScene.skyRect))
        let skyAfter = ImageStats.averageColor(of: output.cropped(to: TestScene.skyRect))
        XCTAssertGreaterThan(skyAfter.x - skyAfter.z, skyBefore.x - skyBefore.z + 0.05, "warmer sky")
        XCTAssertEqual(ImageStats.averageLuminance(of: output.cropped(to: TestScene.groundRect)), ImageStats.averageLuminance(of: Self.scene.cropped(to: TestScene.groundRect)), accuracy: 0.003)
    }

    func testBackgroundColorAndTransparency() throws {
        try XCTSkipUnless(Fixtures.hasReference, "reference masks are generated on CI")
        let hips = try XCTUnwrap(Self.bodyAnalysis.bodies.first?.pose.hipCenter)
        let e = Self.body.extent
        let hipRect = CGRect(x: CGFloat(hips.x) * e.width - 10, y: CGFloat(hips.y) * e.height - 10, width: 20, height: 20)
        let corner = CGRect(x: 0, y: 0, width: 30, height: 30)

        var document = EditDocument()
        document.background.mode = .color
        document.background.color = RGBColor(0.2, 0.4, 0.9)
        let colored = pipeline.apply(document, to: Self.body, analysis: Self.bodyAnalysis)
        let cornerColor = ImageStats.averageColor(of: colored.cropped(to: corner))
        XCTAssertGreaterThan(cornerColor.z, cornerColor.x * 2, "blue background")
        XCTAssertEqual(ImageStats.averageLuminance(of: colored.cropped(to: hipRect)), ImageStats.averageLuminance(of: Self.body.cropped(to: hipRect)), accuracy: 0.01)

        document.background.mode = .transparent
        let cutout = pipeline.apply(document, to: Self.body, analysis: Self.bodyAnalysis)
        XCTAssertLessThan(ImageStats.averageColor(of: cutout.cropped(to: corner)).w, 0.05, "transparent background")
        XCTAssertGreaterThan(ImageStats.averageColor(of: cutout.cropped(to: hipRect)).w, 0.9, "opaque subject")
    }

    func testEnlargeDoublesTheSize() {
        let enlarged = Exporter.enlarged(Self.scene)
        XCTAssertEqual(enlarged.extent.width, 1920)
        XCTAssertEqual(enlarged.extent.height, 1280)
    }

    func testWriteEnhanceSheet() throws {
        var auto = EditDocument()
        AutoEnhance.propose(for: Self.dullScene).apply(to: &auto)
        func sky(_ style: SkyStyle) -> CIImage {
            var document = EditDocument()
            document.sky.style = style
            return pipeline.apply(document, to: Self.scene, analysis: Self.sceneAnalysis)
        }
        var items: [(String, CIImage)] = [
            ("Dull", Self.dullScene),
            ("Auto enhance", pipeline.apply(auto, to: Self.dullScene, analysis: ImageAnalysis(image: Self.dullScene))),
            ("Sky: sunset", sky(.sunset)),
            ("Sky: dramatic", sky(.dramatic)),
            ("Sky: golden", sky(.golden)),
            ("Sky: pastel", sky(.pastel)),
            ("Sky: starry", sky(.night)),
            ("Sky: clear", sky(.clear)),
        ]
        if Fixtures.hasReference {
            var document = EditDocument()
            document.background.mode = .color
            document.background.color = .cream
            items.append(("Background: cream", pipeline.apply(document, to: Self.body, analysis: Self.bodyAnalysis)))
        }
        try ContactSheet.write(items, name: "80-enhance", columns: 4)
    }
}
