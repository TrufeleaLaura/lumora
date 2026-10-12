import XCTest
@testable import LumoraCore

final class LooksTests: XCTestCase {
    func testLibraryIntegrity() {
        let ids = LookLibrary.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "look ids must be unique")
        XCTAssertGreaterThanOrEqual(LookLibrary.all.count, 50)
        for pack in LookPack.allCases where pack != .custom {
            XCTAssertFalse(LookLibrary.looks(in: pack).isEmpty, pack.rawValue)
        }
        for look in LookLibrary.all {
            XCTAssertEqual(look.recipe.mixer.hue.count, 8, look.id)
            XCTAssertEqual(look.recipe.blackWhite.mix.count, 8, look.id)
            XCTAssertNotEqual(look.recipe, LookRecipe(), "\(look.id) does nothing")
            XCTAssertNotNil(LookLibrary.look(id: look.id))
        }
    }

    func testLookSettingsCopyRecipe() {
        let look = LookLibrary.all[3]
        let settings = LookSettings(look: look, amount: 60)
        XCTAssertEqual(settings.recipe, look.recipe)
        XCTAssertEqual(settings.name, look.name)
        XCTAssertTrue(settings.isActive)
        XCTAssertFalse(LookSettings().isActive)
        XCTAssertFalse(LookSettings(look: look, amount: 0).isActive)
    }

    func testLookSurvivesDocumentRoundTrip() throws {
        var document = EditDocument()
        document.look = LookSettings(look: LookLibrary.all[10], amount: 70)
        let decoded = try EditDocument.decode(from: document.jsonData())
        XCTAssertEqual(decoded.look, document.look)
    }

    func testCurveShapesAreValid() {
        for points in [CurveShape.matte(black: 0.1, white: 0.92), CurveShape.s(0.05), CurveShape.s(0.03, black: 0.04)] {
            let sorted = ToneCurveMath.sanitized(points)
            XCTAssertEqual(sorted.count, points.count)
            for x in stride(from: 0.0, through: 1.0, by: 0.05) {
                XCTAssertTrue((0...1).contains(ToneCurveMath.evaluate(points, at: x)))
            }
        }
    }
}

final class CubeLUTTests: XCTestCase {
    private func cubeText(size: Int, transform: (Float, Float, Float) -> (Float, Float, Float)) -> String {
        var lines = ["# test", "TITLE \"Test LUT\"", "LUT_3D_SIZE \(size)", "DOMAIN_MIN 0 0 0", "DOMAIN_MAX 1 1 1"]
        let scale = Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let value = transform(Float(r) / scale, Float(g) / scale, Float(b) / scale)
                    lines.append("\(value.0) \(value.1) \(value.2)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    func testParsesValidCube() throws {
        let lut = try CubeLUT.parse(cubeText(size: 5) { ($0, $1, $2) })
        XCTAssertEqual(lut.title, "Test LUT")
        XCTAssertEqual(lut.size, 5)
        XCTAssertEqual(lut.values.count, 5 * 5 * 5 * 3)
        XCTAssertEqual(lut, CubeLUT.identity(size: 5).withTitle("Test LUT"))
        XCTAssertEqual(lut.cubeData().count, 5 * 5 * 5 * 4)
    }

    func testRejectsBrokenCubes() {
        XCTAssertThrowsError(try CubeLUT.parse("0 0 0\n1 1 1"))
        XCTAssertThrowsError(try CubeLUT.parse("LUT_3D_SIZE 2\n0 0 0\n1 1 1"))
        XCTAssertThrowsError(try CubeLUT.parse("LUT_3D_SIZE 1000"))
    }

    func testStoresRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LUTStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LUTStore(rootURL: root)
        let entry = try store.importCube(text: cubeText(size: 3) { (1 - $0, 1 - $1, 1 - $2) }, name: "Invert")
        XCTAssertEqual(store.list().map(\.id), [entry.id])
        XCTAssertEqual(LUTStore(rootURL: root).lut(id: entry.id)?.size, 3)
        XCTAssertEqual(entry.look.lutID, entry.id)
        try store.delete(entry.id)
        XCTAssertTrue(store.list().isEmpty)
        XCTAssertNil(LUTStore(rootURL: root).lut(id: entry.id))
    }

    func testPresetStoreRoundTripDropsGeometry() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("PresetTests-\(UUID().uuidString)/presets.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = PresetStore(fileURL: file)
        var document = EditDocument()
        document.light.exposure = 0.4
        document.geometry.quarterTurns = 1
        let preset = try store.save(name: "Bright", document: document)
        let loaded = PresetStore(fileURL: file).list()
        XCTAssertEqual(loaded.map(\.id), [preset.id])
        XCTAssertEqual(loaded.first?.document.light.exposure, 0.4)
        XCTAssertEqual(loaded.first?.document.geometry, GeometrySettings())
        try store.delete(preset.id)
        XCTAssertTrue(store.list().isEmpty)
    }
}

private extension CubeLUT {
    func withTitle(_ title: String) -> CubeLUT {
        var copy = self
        copy.title = title
        return copy
    }
}
