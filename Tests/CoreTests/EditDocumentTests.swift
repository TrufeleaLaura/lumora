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

        let decoded = try EditDocument.decode(from: document.jsonData())
        XCTAssertEqual(decoded, document)
    }

    func testDecodingOlderFileFillsMissingSettingsWithDefaults() throws {
        // A file written before "whites", "blacks" and the whole color section existed.
        let json = #"{"formatVersion": 1, "light": {"exposure": 0.7, "contrast": 12}}"#
        let decoded = try EditDocument.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.light.exposure, 0.7)
        XCTAssertEqual(decoded.light.contrast, 12)
        XCTAssertEqual(decoded.light.whites, 0)
        XCTAssertEqual(decoded.color, ColorSettings())
    }

    func testDecodingIgnoresUnknownKeys() throws {
        let json = #"{"formatVersion": 1, "futureFeature": {"x": 1}, "light": {"exposure": -1}}"#
        let decoded = try EditDocument.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.light.exposure, -1)
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

final class EditHistoryTests: XCTestCase {
    private func document(exposure: Double) -> EditDocument {
        var document = EditDocument()
        document.light.exposure = exposure
        return document
    }

    func testUndoRedo() {
        var history = EditHistory()
        let d0 = document(exposure: 0), d1 = document(exposure: 1), d2 = document(exposure: 2)
        history.record(label: "Exposure +1.00", before: d0, after: d1)
        history.record(label: "Exposure +2.00", before: d1, after: d2)

        XCTAssertEqual(history.undo(), d1)
        XCTAssertEqual(history.undo(), d0)
        XCTAssertNil(history.undo())
        XCTAssertEqual(history.redo(), d1)
        XCTAssertTrue(history.canRedo)

        // A new change clears the redo history.
        history.record(label: "Exposure +5.00", before: d1, after: document(exposure: 5))
        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.timeline.map(\.label), ["Exposure +1.00", "Exposure +5.00"])
    }

    func testNoOpChangesAreIgnored() {
        var history = EditHistory()
        history.record(label: "Nothing", before: EditDocument(), after: EditDocument())
        XCTAssertFalse(history.canUndo)
    }

    func testJump() {
        var history = EditHistory()
        let docs = (0...4).map { document(exposure: Double($0)) }
        for i in 1...4 {
            history.record(label: "Step \(i)", before: docs[i - 1], after: docs[i])
        }
        XCTAssertEqual(history.jump(toAppliedCount: 1), docs[1])
        XCTAssertEqual(history.undoSteps.count, 1)
        XCTAssertEqual(history.timeline.count, 4)
        XCTAssertEqual(history.jump(toAppliedCount: 3), docs[3])
        XCTAssertEqual(history.jump(toAppliedCount: 0), docs[0])
        XCTAssertEqual(history.jump(toAppliedCount: 99), docs[4])
    }

    func testLimit() {
        var history = EditHistory(limit: 3)
        for i in 0..<10 {
            history.record(label: "\(i)", before: document(exposure: Double(i)), after: document(exposure: Double(i + 1)))
        }
        XCTAssertEqual(history.undoSteps.map(\.label), ["7", "8", "9"])
    }
}

final class ProjectStoreTests: XCTestCase {
    private var root: URL!
    private var store: ProjectStore!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectStoreTests-\(UUID().uuidString)")
        store = ProjectStore(rootURL: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testCreateSaveListDuplicateDelete() throws {
        let original = Data("fake image bytes".utf8)
        let meta = try store.create(originalData: original, fileExtension: "HEIC", pixelWidth: 4032, pixelHeight: 3024)
        XCTAssertEqual(meta.originalFileName, "original.heic")
        XCTAssertEqual(try store.originalData(for: meta.id), original)
        XCTAssertEqual(try store.document(for: meta.id), EditDocument())

        var document = EditDocument()
        document.light.exposure = 0.8
        try store.save(document: document, for: meta.id)
        XCTAssertEqual(try store.document(for: meta.id), document)

        let copy = try store.duplicate(meta.id)
        XCTAssertNotEqual(copy.id, meta.id)
        XCTAssertEqual(try store.document(for: copy.id), document)
        XCTAssertEqual(Set(store.list().map(\.id)), [meta.id, copy.id])

        try store.delete(meta.id)
        XCTAssertEqual(store.list().map(\.id), [copy.id])
        XCTAssertThrowsError(try store.metadata(for: meta.id))
    }

    func testListIsSortedByModificationDate() throws {
        let first = try store.create(originalData: Data([1]), fileExtension: "jpg", pixelWidth: 10, pixelHeight: 10)
        let second = try store.create(originalData: Data([2]), fileExtension: "jpg", pixelWidth: 10, pixelHeight: 10)
        Thread.sleep(forTimeInterval: 1.1)
        try store.save(document: EditDocument(), for: first.id)
        XCTAssertEqual(store.list().map(\.id), [first.id, second.id])
    }
}
