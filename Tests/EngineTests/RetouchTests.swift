import CoreImage
import LumoraCore
import XCTest
@testable import LumoraEngine

final class RetouchTests: XCTestCase {
    private let pipeline = RenderPipeline()

    /// The test scene with a dark "object" on the ground and a bright spot in the sky.
    private static let damaged: CIImage = {
        let scene = TestScene.image()
        let object = CIImage(color: CIColor(red: 0.02, green: 0.02, blue: 0.03)).cropped(to: CGRect(x: 560, y: 120, width: 44, height: 44))
        return object.composited(over: scene).cropped(to: scene.extent)
    }()
    private static let analysis = ImageAnalysis(image: damaged)

    private func normalized(_ x: CGFloat, _ y: CGFloat) -> SIMD2<Double> {
        SIMD2(Double(x) / Double(TestScene.width), Double(y) / Double(TestScene.height))
    }

    private func stats(_ image: CIImage, _ rect: CGRect) -> (mean: Float, minimum: Float) {
        let read = RenderContext.readFloats(image.cropped(to: rect))
        var sum: Float = 0
        var minimum: Float = .infinity
        let count = read.width * read.height
        for i in 0..<count {
            let luma = 0.2126 * read.pixels[i * 4] + 0.7152 * read.pixels[i * 4 + 1] + 0.0722 * read.pixels[i * 4 + 2]
            sum += luma
            minimum = min(minimum, luma)
        }
        return (sum / Float(max(count, 1)), minimum)
    }

    func testRemoveFillsTheObjectWithItsSurroundings() {
        var document = EditDocument()
        var operation = RetouchOperation(tool: .remove)
        operation.strokes = [BrushStroke(points: [normalized(570, 142), normalized(594, 142)], radius: 34.0 / Double(TestScene.width), feather: 20)]
        document.retouch.operations = [operation]
        let output = pipeline.apply(document, to: Self.damaged, analysis: Self.analysis)

        let objectRect = CGRect(x: 566, y: 126, width: 32, height: 32)
        let ground = stats(TestScene.image(), CGRect(x: 500, y: 100, width: 40, height: 40))
        let before = stats(Self.damaged, objectRect)
        let after = stats(output, objectRect)
        XCTAssertLessThan(before.mean, 0.01)
        XCTAssertEqual(after.mean, ground.mean, accuracy: ground.mean * 0.35, "filled with ground texture")
        XCTAssertGreaterThan(after.minimum, 0.004, "no dark pixels left")
        // Far away nothing changes.
        XCTAssertEqual(stats(output, TestScene.skyRect).mean, stats(Self.damaged, TestScene.skyRect).mean, accuracy: 1e-5)
    }

    func testCloneCopiesTheSource() {
        var document = EditDocument()
        var operation = RetouchOperation(tool: .clone)
        let target = normalized(300, 520)
        let sun = normalized(720, 520)
        operation.strokes = [BrushStroke(points: [target], radius: 18.0 / Double(TestScene.width), feather: 0)]
        operation.sourceOffset = sun - target
        document.retouch.operations = [operation]
        let output = pipeline.apply(document, to: Self.damaged, analysis: Self.analysis)
        let cloned = stats(output, CGRect(x: 292, y: 512, width: 16, height: 16))
        let sunStats = stats(Self.damaged, CGRect(x: 712, y: 512, width: 16, height: 16))
        XCTAssertEqual(cloned.mean, sunStats.mean, accuracy: sunStats.mean * 0.1)
    }

    func testPatchesAreCachedPerOperation() {
        var operation = RetouchOperation(tool: .heal)
        operation.strokes = [BrushStroke(points: [normalized(200, 300)], radius: 0.01)]
        var settings = RetouchSettings()
        settings.operations = [operation]
        let key = RetouchCache.Key(photo: ObjectIdentifier(Self.analysis), operations: [operation], width: TestScene.width, height: TestScene.height)
        XCTAssertNil(RetouchCache.shared.patch(key))
        pipeline.prepareRetouch(settings, input: Self.damaged, analysis: Self.analysis)
        XCTAssertNotNil(RetouchCache.shared.patch(key))
    }

    // MARK: - Contact sheet

    func testWriteRetouchSheet() throws {
        let image = Self.damaged
        func render(_ operations: [RetouchOperation]) -> CIImage {
            var document = EditDocument()
            document.retouch.operations = operations
            return pipeline.apply(document, to: image, analysis: Self.analysis)
        }
        var removeObject = RetouchOperation(tool: .remove)
        removeObject.strokes = [BrushStroke(points: [normalized(570, 142), normalized(594, 142)], radius: 34.0 / Double(TestScene.width), feather: 20)]
        var removeSun = RetouchOperation(tool: .remove)
        removeSun.strokes = [BrushStroke(points: [normalized(720, 520)], radius: 60.0 / Double(TestScene.width), feather: 40)]
        var healPeaks = RetouchOperation(tool: .heal)
        healPeaks.strokes = [BrushStroke(points: [normalized(250, 330), normalized(330, 330)], radius: 14.0 / Double(TestScene.width), feather: 30)]
        var clone = RetouchOperation(tool: .clone)
        clone.strokes = [BrushStroke(points: [normalized(300, 520)], radius: 30.0 / Double(TestScene.width), feather: 50)]
        clone.sourceOffset = normalized(720, 520) - normalized(300, 520)
        try ContactSheet.write([
            ("Damaged", image),
            ("Remove object", render([removeObject])),
            ("Remove sun", render([removeSun])),
            ("Heal across peaks", render([healPeaks])),
            ("Clone sun", render([clone])),
            ("All", render([removeObject, removeSun, healPeaks])),
        ], name: "50-retouch", columns: 3)
    }
}
