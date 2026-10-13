import CoreImage
import LumoraCore
import XCTest
@testable import LumoraEngine

final class CollageRenderTests: XCTestCase {
    func testCollageHasTheAspectSizeAndBackgroundBetweenCells() {
        var settings = CollageSettings()
        settings.layout = .twoColumns
        settings.aspect = .square
        settings.spacing = 100
        settings.margin = 100
        settings.background = .white
        let photo = TestScene.image()
        let canvas = CollageRenderer.render(settings, images: [photo, photo], crops: [], scale: 0.25)
        XCTAssertEqual(canvas.extent.width, 540, accuracy: 0.5)
        XCTAssertEqual(canvas.extent.height, 540, accuracy: 0.5)
        // The gap in the middle and the margin show the background.
        XCTAssertGreaterThan(ImageStats.averageLuminance(of: canvas.cropped(to: CGRect(x: 268, y: 200, width: 4, height: 100))), 0.95)
        XCTAssertGreaterThan(ImageStats.averageLuminance(of: canvas.cropped(to: CGRect(x: 0, y: 0, width: 20, height: 20))), 0.95)
        // Cells hold the photo.
        XCTAssertLessThan(ImageStats.averageLuminance(of: canvas.cropped(to: CGRect(x: 120, y: 200, width: 40, height: 100))), 0.9)
    }

    func testWriteCollageSheet() throws {
        let photos = ["portrait-woman", "portrait-smile", "body-front", "body-back", "body-man", "group"].map { Fixtures.photo($0) }
        func collage(_ layout: CollageLayout, _ aspect: CollageAspect, corners: Double = 0, background: RGBColor = .cream) -> CIImage {
            var settings = CollageSettings()
            settings.layout = layout
            settings.aspect = aspect
            settings.cornerRadius = corners
            settings.background = background
            let images: [CIImage?] = Array(photos.prefix(layout.cells.count))
            return CollageRenderer.render(settings, images: images, crops: [], scale: 0.3)
        }
        try ContactSheet.write([
            ("Side by side 4:5", collage(.twoColumns, .portrait)),
            ("Feature left 1:1", collage(.threeLeft, .square, corners: 40)),
            ("Grid 4", collage(.four, .square, background: .white)),
            ("Moodboard 4:5", collage(.moodboard, .portrait, corners: 25)),
            ("Story three rows", collage(.threeRows, .story, background: .black)),
            ("Grid 6 story", collage(.six, .story, corners: 60)),
        ], name: "72-collage", columns: 3)
    }
}
