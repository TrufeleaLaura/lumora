import CoreImage
import LumoraCore
import XCTest
@testable import LumoraEngine

final class BlemishTests: XCTestCase {
    func testDarkSpotsOnTheCheekAreFoundAndHealed() throws {
        try XCTSkipUnless(Fixtures.hasReference, "reference landmarks are generated on CI")
        let portrait = Fixtures.photo("portrait-woman")
        let face = try XCTUnwrap(Fixtures.faces("portrait-woman").first)
        let eye = FaceLandmarks.centroid(face.leftEye)
        let mouth = FaceLandmarks.centroid(face.outerLips)
        let cheek = SIMD2(eye.x, eye.y - (eye.y - mouth.y) * 0.5)
        let e = portrait.extent
        let spotSize = CGFloat(face.bounds.width) * e.width * 0.018
        // Paint two dark spots on the cheek.
        var damaged = portrait
        var centers: [CGPoint] = []
        for dx in [-1.0, 1.0] {
            let center = CGPoint(x: CGFloat(cheek.x + dx * face.bounds.width * 0.06) * e.width, y: CGFloat(cheek.y) * e.height)
            centers.append(center)
            let spot = CIImage(color: CIColor(red: 0.12, green: 0.05, blue: 0.04))
                .cropped(to: CGRect(x: center.x - spotSize / 2, y: center.y - spotSize / 2, width: spotSize, height: spotSize))
            damaged = spot.composited(over: damaged)
        }
        damaged = damaged.cropped(to: e)
        let analysis = ImageAnalysis(image: damaged, faceLandmarks: Fixtures.faces("portrait-woman"))
        let spots = analysis.blemishSpots(faceIndex: 0)
        for center in centers {
            let normalized = SIMD2(Double(center.x / e.width), Double(center.y / e.height))
            XCTAssertTrue(spots.contains { spot in
                let d: SIMD2<Double> = spot.center - normalized
                return (d.x * d.x + d.y * d.y).squareRoot() < face.bounds.width * 0.03
            }, "the painted spot is found")
        }

        var document = EditDocument()
        document.beauty.allFaces.blemishes = 100
        let healed = RenderPipeline().apply(document, to: damaged, analysis: analysis)
        for center in centers {
            let rect = CGRect(x: center.x - spotSize / 4, y: center.y - spotSize / 4, width: spotSize / 2, height: spotSize / 2)
            let before = ImageStats.averageLuminance(of: damaged.cropped(to: rect))
            let after = ImageStats.averageLuminance(of: healed.cropped(to: rect))
            let skin = ImageStats.averageLuminance(of: portrait.cropped(to: rect))
            XCTAssertGreaterThan(after, before + (skin - before) * 0.6, "the spot is healed toward the skin")
        }
    }
}
