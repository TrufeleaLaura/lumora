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
        let sliders = AdjustmentCatalog.allSliders
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

final class ToneCurveMathTests: XCTestCase {
    func testLinearCurveIsIdentity() {
        for x in stride(from: 0.0, through: 1.0, by: 0.1) {
            XCTAssertEqual(ToneCurveMath.evaluate(ToneCurveSettings.linear, at: x), x, accuracy: 1e-9)
        }
        XCTAssertTrue(ToneCurveMath.isIdentity(ToneCurveSettings()))
    }

    func testCurvePassesThroughPointsAndIsMonotone() {
        let points = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.3, y: 0.15), CurvePoint(x: 0.7, y: 0.9), CurvePoint(x: 1, y: 1)]
        for point in points {
            XCTAssertEqual(ToneCurveMath.evaluate(points, at: point.x), point.y, accuracy: 1e-9)
        }
        var previous = -1.0
        for x in stride(from: 0.0, through: 1.0, by: 0.005) {
            let y = ToneCurveMath.evaluate(points, at: x)
            XCTAssertGreaterThanOrEqual(y, previous - 1e-12)
            XCTAssertTrue((0...1).contains(y))
            previous = y
        }
    }

    func testUnsortedAndDuplicatePointsAreSanitized() {
        let points = [CurvePoint(x: 1, y: 1), CurvePoint(x: 0.5, y: 0.6), CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.7)]
        XCTAssertEqual(ToneCurveMath.sanitized(points).count, 3)
        XCTAssertEqual(ToneCurveMath.evaluate(points, at: 0.5), 0.7, accuracy: 1e-9)
    }

    func testParametricKeepsEndpointsAndMovesRegions() {
        var settings = ToneCurveSettings()
        settings.shadows = 100
        settings.highlights = -100
        XCTAssertEqual(ToneCurveMath.parametric(settings, at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(ToneCurveMath.parametric(settings, at: 1), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(ToneCurveMath.parametric(settings, at: 0.15), 0.15)
        XCTAssertLessThan(ToneCurveMath.parametric(settings, at: 0.85), 0.85)
        XCTAssertFalse(ToneCurveMath.isIdentity(settings))
    }

    func testLookupTableAppliesChannelCurves() {
        var settings = ToneCurveSettings()
        settings.red = [CurvePoint(x: 0, y: 0.2), CurvePoint(x: 1, y: 1)]
        let table = ToneCurveMath.lookupTable(settings, count: 256)
        XCTAssertEqual(table.count, 256)
        XCTAssertEqual(table[0].0, 0.2, accuracy: 1e-9)
        XCTAssertEqual(table[0].1, 0, accuracy: 1e-9)
        XCTAssertEqual(table[255].2, 1, accuracy: 1e-9)
    }

    func testHSLConversion() {
        let red = ColorMath.hslToRGB(hue: 0, saturation: 1, lightness: 0.5)
        XCTAssertEqual(red.0, 1, accuracy: 1e-9)
        XCTAssertEqual(red.1, 0, accuracy: 1e-9)
        let cyan = ColorMath.hslToRGB(hue: 180, saturation: 1, lightness: 0.5)
        XCTAssertEqual(cyan.0, 0, accuracy: 1e-9)
        XCTAssertEqual(cyan.2, 1, accuracy: 1e-9)
        let direction = ColorMath.oklabDirection(forWheelHue: 0)
        XCTAssertEqual(direction.0 * direction.0 + direction.1 * direction.1, 1, accuracy: 1e-6)
        XCTAssertGreaterThan(direction.0, 0) // red points to +a
    }
}

final class GeometryMathTests: XCTestCase {
    func testCoverScale() {
        XCTAssertEqual(GeometryMath.coverScale(width: 100, height: 100, degrees: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(GeometryMath.coverScale(width: 100, height: 100, degrees: 45), 2.0.squareRoot(), accuracy: 1e-9)
        XCTAssertGreaterThan(GeometryMath.coverScale(width: 300, height: 200, degrees: -10), 1)
    }

    func testAspectCropFitsAndHasRightRatio() {
        let crop = GeometryMath.crop(aspect: 1, imageWidth: 300, imageHeight: 200)
        XCTAssertEqual(crop.width * 300, crop.height * 200, accuracy: 1e-6)
        XCTAssertEqual(crop.height, 1, accuracy: 1e-9)
        XCTAssertEqual(crop.x, (1 - crop.width) / 2, accuracy: 1e-9)

        let wide = GeometryMath.crop(aspect: 16.0 / 9.0, imageWidth: 300, imageHeight: 200)
        XCTAssertEqual(wide.width, 1, accuracy: 1e-9)
        XCTAssertEqual(wide.width * 300 / (wide.height * 200), 16.0 / 9.0, accuracy: 1e-6)
    }

    func testRotatedAspectPresets() {
        XCTAssertEqual(AspectRatioPreset.portrait4x5.rotated, .landscape5x4)
        XCTAssertEqual(AspectRatioPreset.landscape16x9.rotated, .portrait9x16)
        XCTAssertEqual(AspectRatioPreset.square.rotated, .square)
        for preset in AspectRatioPreset.allCases {
            XCTAssertEqual(preset.rotated.rotated, preset)
        }
    }

    func testHomographyMapsCorners() {
        let quad = [(10.0, 0.0), (90.0, 5.0), (80.0, 100.0), (20.0, 95.0)]
        let m = GeometryMath.homography(quad[0], quad[1], quad[2], quad[3])
        for (corner, target) in zip([(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)], quad) {
            let mapped = GeometryMath.apply(m, u: corner.0, v: corner.1)
            XCTAssertEqual(mapped.0, target.0, accuracy: 1e-9)
            XCTAssertEqual(mapped.1, target.1, accuracy: 1e-9)
        }
        // A rectangle gives an affine map (no projective terms).
        let affine = GeometryMath.homography((0, 0), (4, 0), (4, 2), (0, 2))
        XCTAssertEqual(affine.w.0, 0, accuracy: 1e-12)
        XCTAssertEqual(GeometryMath.apply(affine, u: 0.5, v: 0.5).0, 2, accuracy: 1e-12)
    }

    func testCropRectClamping() {
        let clamped = CropRect(x: 0.9, y: -0.2, width: 0.5, height: 0.01).clamped()
        XCTAssertEqual(clamped.x + clamped.width, 1, accuracy: 1e-9)
        XCTAssertEqual(clamped.y, 0, accuracy: 1e-9)
        XCTAssertEqual(clamped.height, 0.05, accuracy: 1e-9)
        XCTAssertTrue(GeometrySettings().isIdentity)
    }
}
