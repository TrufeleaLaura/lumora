import CoreImage
import LumoraCore
import XCTest
@testable import LumoraEngine

/// The canvas draws pipeline output scaled and moved. Core Image may reorder such transforms
/// with filters, so every stage must give the same result when transformed afterwards, and
/// must not leak anything outside its own extent.
final class TransformRobustnessTests: XCTestCase {
    private static let scene = TestScene.image()
    private static let analysis = ImageAnalysis(image: scene)

    private let background = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6))
        .cropped(to: CGRect(x: 0, y: 0, width: 1400, height: 1000))
    private let transform = CGAffineTransform(scaleX: 0.5, y: 0.5).concatenating(CGAffineTransform(translationX: 300, y: 200))

    private func average(_ image: CIImage, _ rect: CGRect) -> SIMD4<Float> {
        ImageStats.averageColor(of: image.cropped(to: rect), context: RenderContext.analysis)
    }

    func testEveryStageIsStableUnderLaterTransforms() {
        let cases: [(String, (inout EditDocument) -> Void)] = [
            ("distortion +", { $0.optics.distortion = 80 }),
            ("distortion -", { $0.optics.distortion = -80 }),
            ("lens vignetting", { $0.optics.vignetteCorrection = 80 }),
            ("defringe", { $0.optics.defringe = 80 }),
            ("vignette", { $0.effects.vignette = -80 }),
            ("grain", { $0.effects.grain = 60 }),
            ("fade", { $0.effects.fade = 50 }),
            ("dehaze +", { $0.effects.dehaze = 60 }),
            ("dehaze -", { $0.effects.dehaze = -60 }),
            ("clarity", { $0.effects.clarity = 80 }),
            ("texture", { $0.effects.texture = 80 }),
            ("highlights/shadows", { $0.light.highlights = -80; $0.light.shadows = 60 }),
            ("tone", { $0.light.exposure = 0.5; $0.light.contrast = 30 }),
            ("curve", { $0.curve.master = CurveShape.s(0.05) }),
            ("color", { $0.color.vibrance = 50; $0.grading.shadows = GradingWheel(hue: 200, saturation: 40) }),
            ("noise reduction", { $0.detail.noiseReduction = 60; $0.detail.colorNoiseReduction = 60 }),
            ("sharpening", { $0.detail.sharpening = 100 }),
            ("rotate + crop", { $0.geometry.quarterTurns = 1; $0.geometry.crop = CropRect(x: 0.1, y: 0.1, width: 0.7, height: 0.6) }),
            ("straighten + perspective", { $0.geometry.straighten = 7; $0.geometry.vertical = 50 }),
        ]

        for (name, change) in cases {
            var document = EditDocument()
            change(&document)
            let output = RenderPipeline().apply(document, to: Self.scene, analysis: Self.analysis)
            let reference = RenderContext.materialize(output, context: RenderContext.shared)

            let live = output.transformed(by: transform).composited(over: background)
            let expected = reference.transformed(by: transform).composited(over: background)
            let placed = output.extent.applying(transform)

            // Nothing outside the placed photo may change.
            for outside in [CGRect(x: 10, y: 10, width: 200, height: 150), CGRect(x: placed.maxX + 20, y: placed.maxY + 20, width: 150, height: 150)] {
                let difference = average(live, outside) - average(background, outside)
                XCTAssertLessThan(abs(difference.x) + abs(difference.y) + abs(difference.z), 0.003, "\(name): leaked outside its extent")
            }

            // Inside, each quadrant must match the pre-rendered result (no shifts or rescaling).
            let inner = placed.insetBy(dx: 8, dy: 8)
            let quadrants = [
                CGRect(x: inner.minX, y: inner.minY, width: inner.width / 2, height: inner.height / 2),
                CGRect(x: inner.midX, y: inner.minY, width: inner.width / 2, height: inner.height / 2),
                CGRect(x: inner.minX, y: inner.midY, width: inner.width / 2, height: inner.height / 2),
                CGRect(x: inner.midX, y: inner.midY, width: inner.width / 2, height: inner.height / 2),
            ]
            for quadrant in quadrants {
                let a = average(live, quadrant)
                let b = average(expected, quadrant)
                XCTAssertEqual(a.x, b.x, accuracy: 0.015, "\(name): red differs in \(quadrant)")
                XCTAssertEqual(a.y, b.y, accuracy: 0.015, "\(name): green differs in \(quadrant)")
                XCTAssertEqual(a.z, b.z, accuracy: 0.015, "\(name): blue differs in \(quadrant)")
            }
        }
    }
}
