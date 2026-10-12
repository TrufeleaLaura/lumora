import CoreImage
import LumoraCore
import XCTest
@testable import LumoraEngine

final class LookTests: XCTestCase {
    private static let scene = TestScene.image()
    private static let analysis = ImageAnalysis(image: scene)

    private func render(_ document: EditDocument, pipeline: RenderPipeline = RenderPipeline()) -> CIImage {
        pipeline.apply(document, to: Self.scene, analysis: Self.analysis)
    }

    private func difference(_ a: CIImage, _ b: CIImage, _ rect: CGRect) -> Float {
        let x = ImageStats.averageColor(of: a.cropped(to: rect))
        let y = ImageStats.averageColor(of: b.cropped(to: rect))
        return abs(x.x - y.x) + abs(x.y - y.y) + abs(x.z - y.z)
    }

    func testEveryLookChangesThePhoto() {
        for look in LookLibrary.all {
            var document = EditDocument()
            document.look = LookSettings(look: look)
            let output = render(document)
            let changed = [TestScene.skyRect, TestScene.groundRect, TestScene.patchRect(6)].map { difference(output, Self.scene, $0) }.max() ?? 0
            XCTAssertGreaterThan(changed, 0.01, "\(look.name) looks like the original")
            XCTAssertEqual(output.extent, Self.scene.extent, look.name)
        }
    }

    func testStrengthBlendsTowardOriginal() {
        let look = LookLibrary.look(id: "moody.dark-teal")!
        var full = EditDocument()
        full.look = LookSettings(look: look, amount: 100)
        var half = full
        half.look.amount = 50
        let fullDifference = difference(render(full), Self.scene, TestScene.groundRect)
        let halfDifference = difference(render(half), Self.scene, TestScene.groundRect)
        XCTAssertGreaterThan(halfDifference, fullDifference * 0.25)
        XCTAssertLessThan(halfDifference, fullDifference * 0.8)
    }

    func testIdentityLUTChangesNothingAndInvertingLUTInverts() {
        let identity = CubeLUT.identity(size: 17)
        var invertedValues = identity.values
        for i in invertedValues.indices { invertedValues[i] = 1 - invertedValues[i] }
        let inverted = CubeLUT(title: "Invert", size: 17, values: invertedValues)
        let pipeline = RenderPipeline(lutProvider: { $0 == "identity" ? identity : ($0 == "invert" ? inverted : nil) })

        var document = EditDocument()
        document.look = LookSettings(lookID: "identity", name: "Identity", lutID: "identity")
        XCTAssertLessThan(difference(render(document, pipeline: pipeline), Self.scene, TestScene.patchRect(0)), 0.02)

        document.look = LookSettings(lookID: "invert", name: "Invert", lutID: "invert")
        let red = ImageStats.averageColor(of: render(document, pipeline: pipeline).cropped(to: TestScene.patchRect(0)))
        XCTAssertLessThan(red.x, red.z) // red became cyan
    }

    func testLookGrainAndFadeAreMerged() {
        var document = EditDocument()
        document.look = LookSettings(look: LookLibrary.look(id: "film.polaroid")!, amount: 100)
        let effects = RenderPipeline().effectiveEffects(document)
        XCTAssertGreaterThan(effects.fade, 0)
        XCTAssertGreaterThan(effects.grain, 0)
        XCTAssertLessThan(effects.vignette, 0)
        document.look.amount = 0
        XCTAssertEqual(RenderPipeline().effectiveEffects(document), EffectsSettings())
    }

    func testWriteLookSheets() throws {
        for pack in LookPack.allCases where pack != .custom {
            var items: [(String, CIImage)] = [("Original", Self.scene)]
            for look in LookLibrary.looks(in: pack) {
                var document = EditDocument()
                document.look = LookSettings(look: look)
                items.append((look.name, render(document)))
            }
            try ContactSheet.write(items, name: "10-looks-\(pack.rawValue)")
        }
    }
}
