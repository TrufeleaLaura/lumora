import XCTest
@testable import LumoraCore

final class EditDocumentTests: XCTestCase {
    func testDefaultDocumentIsIdentity() {
        XCTAssertTrue(EditDocument().isIdentity)
        var document = EditDocument()
        document.light.exposure = 0.5
        XCTAssertFalse(document.isIdentity)
    }

    func testCodableRoundTrip() throws {
        var document = EditDocument()
        document.light.exposure = 1.25
        document.light.contrast = -30
        document.color.temperature = 40
        document.color.saturation = -100

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(EditDocument.self, from: data)
        XCTAssertEqual(decoded, document)
    }

    func testUndoRedo() {
        var stack = UndoStack<Int>()
        var value = 0

        stack.record(value); value = 1
        stack.record(value); value = 2

        value = stack.undo(current: value)!
        XCTAssertEqual(value, 1)
        value = stack.undo(current: value)!
        XCTAssertEqual(value, 0)
        XCTAssertNil(stack.undo(current: value))

        value = stack.redo(current: value)!
        XCTAssertEqual(value, 1)
        XCTAssertTrue(stack.canRedo)

        // A new change clears the redo history.
        stack.record(value); value = 5
        XCTAssertFalse(stack.canRedo)
        let restored = stack.undo(current: value)
        XCTAssertEqual(restored, 1)
    }

    func testUndoLimit() {
        var stack = UndoStack<Int>(limit: 3)
        for i in 0..<10 { stack.record(i) }
        XCTAssertEqual(stack.undoStates, [7, 8, 9])
    }

    func testSliderFormatting() {
        let ev = AdjustmentCatalog.light.sliders.first { $0.id == "exposure" }!
        XCTAssertEqual(ev.formatted(0), "0.00")
        XCTAssertEqual(ev.formatted(1.5), "+1.50")
        XCTAssertEqual(ev.formatted(-0.25), "-0.25")

        let contrast = AdjustmentCatalog.light.sliders.first { $0.id == "contrast" }!
        XCTAssertEqual(contrast.formatted(0), "0")
        XCTAssertEqual(contrast.formatted(24.6), "+25")
        XCTAssertEqual(contrast.formatted(-10), "-10")
    }

    func testCatalogIDsAreUniqueAndDefaultsInRange() {
        let sliders = AdjustmentCatalog.groups.flatMap(\.sliders)
        XCTAssertEqual(Set(sliders.map(\.id)).count, sliders.count)
        for slider in sliders {
            XCTAssertTrue(slider.range.contains(slider.defaultValue), slider.id)
            XCTAssertEqual(EditDocument()[keyPath: slider.keyPath], slider.defaultValue, slider.id)
        }
    }
}
