import XCTest
@testable import LumoraCore

final class CollageTests: XCTestCase {
    func testCellsStayInsideTheCanvasWithGaps() {
        for layout in CollageLayout.allCases {
            var settings = CollageSettings()
            settings.layout = layout
            settings.spacing = 50
            settings.margin = 50
            let rects = settings.cellRects(width: 2160, height: 2700)
            XCTAssertEqual(rects.count, layout.cells.count)
            for rect in rects {
                XCTAssertGreaterThanOrEqual(rect.x, 0, "\(layout)")
                XCTAssertGreaterThanOrEqual(rect.y, 0, "\(layout)")
                XCTAssertLessThanOrEqual(rect.x + rect.width, 2160 + 1e-6, "\(layout)")
                XCTAssertLessThanOrEqual(rect.y + rect.height, 2700 + 1e-6, "\(layout)")
            }
            // No two cells overlap.
            for i in rects.indices {
                for j in rects.indices where j > i {
                    let a = rects[i], b = rects[j]
                    let overlapX = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
                    let overlapY = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
                    XCTAssertFalse(overlapX > 0.5 && overlapY > 0.5, "\(layout) cells \(i) and \(j) overlap")
                }
            }
        }
    }

    func testImageAlwaysCoversItsCell() {
        let cell = CGRectValue(x: 100, y: 100, width: 400, height: 600)
        var crop = CollageCrop()
        crop.offset = SIMD2(5, -5)
        crop.zoom = 1.5
        let rect = CollageMath.imageRect(imageWidth: 3000, imageHeight: 2000, cell: cell, crop: crop)
        XCTAssertLessThanOrEqual(rect.x, cell.x + 1e-9)
        XCTAssertLessThanOrEqual(rect.y, cell.y + 1e-9)
        XCTAssertGreaterThanOrEqual(rect.x + rect.width, cell.x + cell.width - 1e-9)
        XCTAssertGreaterThanOrEqual(rect.y + rect.height, cell.y + cell.height - 1e-9)
        XCTAssertEqual(rect.width / rect.height, 1.5, accuracy: 1e-9, "aspect kept")
    }

    func testFeedOrderPutsNewPostsFirst() {
        let old = ProjectMetadata(createdAt: Date(timeIntervalSince1970: 100), originalFileName: "a.jpg", pixelWidth: 1, pixelHeight: 1)
        let older = ProjectMetadata(createdAt: Date(timeIntervalSince1970: 50), originalFileName: "b.jpg", pixelWidth: 1, pixelHeight: 1)
        let new = ProjectMetadata(createdAt: Date(timeIntervalSince1970: 200), originalFileName: "c.jpg", pixelWidth: 1, pixelHeight: 1)
        let removed = UUID()
        let feed = ProjectStore.feed([old, older, new], order: [older.id, removed, old.id])
        XCTAssertEqual(feed.map(\.id), [new.id, older.id, old.id])
    }
}
