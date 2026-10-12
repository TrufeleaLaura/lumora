import CoreImage
import LumoraCore
import XCTest
@testable import LumoraEngine

/// Phase 2 tools on the synthetic landscape: numeric behavior checks + contact sheets for review.
final class AdjustmentTests: XCTestCase {
    private static let scene = TestScene.image()
    private static let analysis = ImageAnalysis(image: scene)
    private let pipeline = RenderPipeline()

    private func render(_ change: (inout EditDocument) -> Void) -> CIImage {
        var document = EditDocument()
        change(&document)
        return pipeline.apply(document, to: Self.scene, scale: 1, analysis: Self.analysis)
    }

    private func luminance(_ image: CIImage, _ rect: CGRect) -> Float {
        ImageStats.perceptualLuminanceStats(of: image.cropped(to: rect)).mean
    }

    private func deviation(_ image: CIImage, _ rect: CGRect) -> Float {
        ImageStats.perceptualLuminanceStats(of: image.cropped(to: rect)).deviation
    }

    private func color(_ image: CIImage, _ rect: CGRect) -> SIMD4<Float> {
        ImageStats.averageColor(of: image.cropped(to: rect))
    }

    // MARK: - Light

    func testHighlightsRecoverSkyMoreThanShadows() {
        let base = Self.scene
        let edited = render { $0.light.highlights = -100 }
        let skyDrop = luminance(base, TestScene.skyRect) - luminance(edited, TestScene.skyRect)
        let shadowDrop = luminance(base, TestScene.shadowRect) - luminance(edited, TestScene.shadowRect)
        XCTAssertGreaterThan(skyDrop, 0.04)
        XCTAssertLessThan(abs(shadowDrop), skyDrop * 0.25)
    }

    func testShadowsLiftDarkAreasMoreThanSky() {
        let base = Self.scene
        let edited = render { $0.light.shadows = 100 }
        let shadowLift = luminance(edited, TestScene.shadowRect) - luminance(base, TestScene.shadowRect)
        let skyLift = luminance(edited, TestScene.skyRect) - luminance(base, TestScene.skyRect)
        XCTAssertGreaterThan(shadowLift, 0.05)
        XCTAssertLessThan(abs(skyLift), shadowLift * 0.3)
    }

    func testShadowsKeepLocalDetail() {
        let edited = render { $0.light.shadows = 100 }
        XCTAssertGreaterThan(deviation(edited, TestScene.shadowRect), deviation(Self.scene, TestScene.shadowRect))
    }

    // MARK: - Effects

    func testClarityAndTextureIncreaseLocalContrast() {
        let base = deviation(Self.scene, TestScene.groundRect)
        XCTAssertGreaterThan(deviation(render { $0.effects.clarity = 100 }, TestScene.groundRect), base * 1.08)
        XCTAssertGreaterThan(deviation(render { $0.effects.texture = 100 }, TestScene.groundRect), base * 1.08)
        XCTAssertLessThan(deviation(render { $0.effects.texture = -100 }, TestScene.groundRect), base)
    }

    func testDehazeRevealsDetailInHazyMountains() {
        let base = deviation(Self.scene, TestScene.mountainRect)
        XCTAssertGreaterThan(deviation(render { $0.effects.dehaze = 80 }, TestScene.mountainRect), base * 1.2)
        XCTAssertLessThan(deviation(render { $0.effects.dehaze = -80 }, TestScene.mountainRect), base)
    }

    func testVignetteDarkensCorners() {
        let edited = render { $0.effects.vignette = -100 }
        let corner = CGRect(x: 0, y: 600, width: 40, height: 40)
        let ratio = luminance(edited, corner) / luminance(Self.scene, corner)
        XCTAssertLessThan(ratio, 0.8)
        let center = CGRect(x: 460, y: 300, width: 40, height: 40)
        XCTAssertEqual(luminance(edited, center), luminance(Self.scene, center), accuracy: 0.02)
    }

    func testGrainAddsTexture() {
        let sky = CGRect(x: 60, y: 580, width: 100, height: 40)
        XCTAssertGreaterThan(deviation(render { $0.effects.grain = 80 }, sky), deviation(Self.scene, sky) * 1.3)
    }

    func testFadeLiftsBlacks() {
        XCTAssertGreaterThan(luminance(render { $0.effects.fade = 80 }, TestScene.shadowRect), luminance(Self.scene, TestScene.shadowRect) + 0.03)
    }

    // MARK: - Detail

    func testNoiseReductionSmoothsNoise() {
        let base = deviation(Self.scene, TestScene.skyRect)
        XCTAssertLessThan(deviation(render { $0.detail.noiseReduction = 80 }, TestScene.skyRect), base * 0.8)
    }

    func testSharpeningIncreasesDetail() {
        let base = deviation(Self.scene, TestScene.groundRect)
        XCTAssertGreaterThan(deviation(render { $0.detail.sharpening = 120 }, TestScene.groundRect), base)
    }

    // MARK: - Color

    func testMixerDesaturatesOnlyTheChosenBand() {
        let edited = render { $0.mixer.saturation[HueBand.blue.rawValue] = -100 }
        let blue = color(edited, TestScene.patchRect(4))
        XCTAssertEqual(blue.x, blue.z, accuracy: 0.03)
        let red = color(edited, TestScene.patchRect(0))
        let originalRed = color(Self.scene, TestScene.patchRect(0))
        XCTAssertEqual(red.x, originalRed.x, accuracy: 0.02)
        XCTAssertEqual(red.y, originalRed.y, accuracy: 0.02)
    }

    func testBlackAndWhiteIsNeutral() {
        let edited = render { $0.blackWhite.isEnabled = true }
        for index in 0..<TestImages.patchColors.count {
            let c = color(edited, TestScene.patchRect(index))
            XCTAssertEqual(c.x, c.y, accuracy: 0.01, "patch \(index)")
            XCTAssertEqual(c.y, c.z, accuracy: 0.01, "patch \(index)")
        }
    }

    func testGradingTintsShadowsAndHighlightsSeparately() {
        let edited = render {
            $0.grading.shadows = GradingWheel(hue: 200, saturation: 80)   // teal
            $0.grading.highlights = GradingWheel(hue: 30, saturation: 80) // orange
        }
        let shadow = color(edited, TestScene.shadowRect)
        let originalShadow = color(Self.scene, TestScene.shadowRect)
        XCTAssertGreaterThan(shadow.z - shadow.x, originalShadow.z - originalShadow.x)
        let sky = color(edited, TestScene.skyRect)
        let originalSky = color(Self.scene, TestScene.skyRect)
        XCTAssertGreaterThan(sky.x - sky.z, originalSky.x - originalSky.z)
    }

    func testVibranceBoostsMutedColorsMore() {
        let edited = render { $0.color.vibrance = 100 }
        func chroma(_ c: SIMD4<Float>) -> Float { max(c.x, max(c.y, c.z)) - min(c.x, min(c.y, c.z)) }
        let mutedGain = chroma(color(edited, TestScene.mountainRect)) / max(chroma(color(Self.scene, TestScene.mountainRect)), 1e-4)
        let vividGain = chroma(color(edited, TestScene.patchRect(0))) / max(chroma(color(Self.scene, TestScene.patchRect(0))), 1e-4)
        XCTAssertGreaterThan(mutedGain, vividGain)
    }

    // MARK: - Curves

    func testSCurveIncreasesContrast() {
        let edited = render {
            $0.curve.master = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.25, y: 0.18), CurvePoint(x: 0.75, y: 0.84), CurvePoint(x: 1, y: 1)]
        }
        func spread(_ image: CIImage) -> Float {
            luminance(image, TestScene.skyRect) - luminance(image, TestScene.groundRect)
        }
        XCTAssertGreaterThan(spread(edited), spread(Self.scene))
    }

    func testRedChannelCurveAddsRed() {
        let edited = render { $0.curve.red = [CurvePoint(x: 0, y: 0.1), CurvePoint(x: 1, y: 1)] }
        let c = color(edited, TestScene.groundRect)
        let o = color(Self.scene, TestScene.groundRect)
        XCTAssertGreaterThan(c.x, o.x)
        XCTAssertEqual(c.y, o.y, accuracy: 0.01)
    }

    // MARK: - Optics

    func testLensVignetteCorrectionBrightensCorners() {
        let edited = render { $0.optics.vignetteCorrection = 100 }
        let corner = CGRect(x: 0, y: 600, width: 40, height: 40)
        XCTAssertGreaterThan(luminance(edited, corner), luminance(Self.scene, corner))
    }

    func testDistortionKeepsImageFilled() {
        for amount in [-100.0, 100.0] {
            let edited = render { $0.optics.distortion = amount }
            XCTAssertEqual(edited.extent, Self.scene.extent)
            let corner = color(edited, CGRect(x: 0, y: 0, width: 8, height: 8))
            XCTAssertGreaterThan(corner.w, 0.99, "corner must not be transparent (distortion \(amount))")
        }
    }

    // MARK: - Contact sheets

    private func crop(_ image: CIImage, _ rect: CGRect, zoom: CGFloat = 3) -> CIImage {
        image.cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: zoom, y: zoom))
    }

    func testWriteLightSheet() throws {
        try ContactSheet.write([
            ("Original", Self.scene),
            ("Exposure +1", render { $0.light.exposure = 1 }),
            ("Contrast +60", render { $0.light.contrast = 60 }),
            ("Contrast -60", render { $0.light.contrast = -60 }),
            ("Highlights -100", render { $0.light.highlights = -100 }),
            ("Shadows +100", render { $0.light.shadows = 100 }),
            ("Whites +60 Blacks -60", render { $0.light.whites = 60; $0.light.blacks = -60 }),
            ("HDR look", render { $0.light.highlights = -90; $0.light.shadows = 80; $0.effects.clarity = 30 }),
        ], name: "02-light")
    }

    func testWriteColorSheet() throws {
        try ContactSheet.write([
            ("Original", Self.scene),
            ("Vibrance +80", render { $0.color.vibrance = 80 }),
            ("Saturation -60", render { $0.color.saturation = -60 }),
            ("Mixer: blue sat -100", render { $0.mixer.saturation[HueBand.blue.rawValue] = -100 }),
            ("Mixer: green hue +100", render { $0.mixer.hue[HueBand.green.rawValue] = 100; $0.mixer.hue[HueBand.yellow.rawValue] = 60 }),
            ("Mixer: blue lum -60", render { $0.mixer.luminance[HueBand.blue.rawValue] = -60 }),
            ("Grading teal/orange", render {
                $0.grading.shadows = GradingWheel(hue: 195, saturation: 60)
                $0.grading.highlights = GradingWheel(hue: 32, saturation: 55)
            }),
            ("B&W (red +60, blue -40)", render {
                $0.blackWhite.isEnabled = true
                $0.blackWhite.mix[HueBand.red.rawValue] = 60
                $0.blackWhite.mix[HueBand.blue.rawValue] = -40
            }),
        ], name: "03-color")
    }

    func testWriteEffectsSheet() throws {
        try ContactSheet.write([
            ("Original", Self.scene),
            ("Texture +100", render { $0.effects.texture = 100 }),
            ("Clarity +100", render { $0.effects.clarity = 100 }),
            ("Clarity -100", render { $0.effects.clarity = -100 }),
            ("Dehaze +80", render { $0.effects.dehaze = 80 }),
            ("Dehaze -60", render { $0.effects.dehaze = -60 }),
            ("Vignette -80", render { $0.effects.vignette = -80 }),
            ("Grain 60 + Fade 40", render { $0.effects.grain = 60; $0.effects.fade = 40 }),
        ], name: "04-effects")
    }

    func testWriteDetailSheet() throws {
        let rect = CGRect(x: 280, y: 160, width: 120, height: 80)
        try ContactSheet.write([
            ("Original (3x)", crop(Self.scene, rect)),
            ("Noise reduction 70", crop(render { $0.detail.noiseReduction = 70 }, rect)),
            ("Color noise 80", crop(render { $0.detail.colorNoiseReduction = 80 }, rect)),
            ("Sharpening 100", crop(render { $0.detail.sharpening = 100 }, rect)),
        ], name: "05-detail")
    }

    func testWriteCurveAndOpticsSheet() throws {
        try ContactSheet.write([
            ("S-curve", render {
                $0.curve.master = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.25, y: 0.18), CurvePoint(x: 0.75, y: 0.84), CurvePoint(x: 1, y: 1)]
            }),
            ("Matte curve", render {
                $0.curve.master = [CurvePoint(x: 0, y: 0.12), CurvePoint(x: 0.5, y: 0.52), CurvePoint(x: 1, y: 0.94)]
            }),
            ("Parametric lights +60", render { $0.curve.lights = 60; $0.curve.darks = -40 }),
            ("Blue curve lift", render { $0.curve.blue = [CurvePoint(x: 0, y: 0.15), CurvePoint(x: 1, y: 0.9)] }),
            ("Distortion +100", render { $0.optics.distortion = 100 }),
            ("Distortion -100", render { $0.optics.distortion = -100 }),
            ("Lens vignetting +100", render { $0.optics.vignetteCorrection = 100 }),
            ("Defringe 100", render { $0.optics.defringe = 100 }),
        ], name: "06-curves-optics")
    }
}
