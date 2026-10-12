import CoreImage
import ImageIO
import LumoraCore
import XCTest
@testable import LumoraEngine

final class ExporterTests: XCTestCase {
    private let chart = TestImages.colorChart()

    private let sourceProperties: [String: Any] = [
        kCGImagePropertyOrientation as String: 6,
        kCGImagePropertyExifDictionary as String: [
            kCGImagePropertyExifLensModel as String: "Test Lens 24mm",
            kCGImagePropertyExifISOSpeedRatings as String: [100],
        ],
        kCGImagePropertyTIFFDictionary as String: [
            kCGImagePropertyTIFFMake as String: "Apple",
            kCGImagePropertyTIFFOrientation as String: 6,
        ],
        kCGImagePropertyGPSDictionary as String: [
            kCGImagePropertyGPSLatitude as String: 46.77,
            kCGImagePropertyGPSLatitudeRef as String: "N",
            kCGImagePropertyGPSLongitude as String: 23.59,
            kCGImagePropertyGPSLongitudeRef as String: "E",
        ],
    ]

    private func readProperties(_ data: Data) -> [String: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return [:] }
        return properties
    }

    func testKeepAllMetadataResetsOrientationAndKeepsExifAndGPS() throws {
        let options = ExportOptions(format: .jpeg, quality: 0.9, size: .original, metadata: .keepAll)
        let data = try Exporter.export(chart, options: options, sourceProperties: sourceProperties)
        let properties = readProperties(data)
        XCTAssertEqual(properties[kCGImagePropertyOrientation as String] as? Int ?? 1, 1)
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        XCTAssertEqual(exif?[kCGImagePropertyExifLensModel as String] as? String, "Test Lens 24mm")
        XCTAssertNotNil(properties[kCGImagePropertyGPSDictionary as String])
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        XCTAssertEqual(tiff?[kCGImagePropertyTIFFSoftware as String] as? String, "Lumora")
    }

    func testRemoveLocationDropsGPS() throws {
        let options = ExportOptions(format: .jpeg, quality: 0.9, size: .original, metadata: .removeLocation)
        let data = try Exporter.export(chart, options: options, sourceProperties: sourceProperties)
        let properties = readProperties(data)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        XCTAssertEqual(exif?[kCGImagePropertyExifLensModel as String] as? String, "Test Lens 24mm")
    }

    func testRemoveAllDropsCameraData() throws {
        let options = ExportOptions(format: .jpeg, quality: 0.9, size: .original, metadata: .removeAll)
        let data = try Exporter.export(chart, options: options, sourceProperties: sourceProperties)
        let properties = readProperties(data)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifLensModel as String])
    }

    func testResizeLimitsLongEdge() throws {
        let big = chart.transformed(by: CGAffineTransform(scaleX: 4, y: 4)) // 2880 x 1920
        let options = ExportOptions(format: .png, size: .social, metadata: .removeAll)
        let data = try Exporter.export(big, options: options)
        let properties = readProperties(data)
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth as String] as? Int, 1080)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight as String] as? Int, 720)
    }

    func testAllFormatsEncode() throws {
        for format in ExportFormat.allCases where format != .heic {
            let data = try Exporter.export(chart, options: ExportOptions(format: format, metadata: .removeAll))
            XCTAssertGreaterThan(data.count, 1000, format.rawValue)
            XCTAssertEqual(Exporter.fileExtension(forEncoded: data).map { $0 == "jpeg" ? "jpg" : $0 }.map { $0 == "tif" ? "tiff" : $0 }, format.fileExtension, format.rawValue)
        }
    }

    func testThumbnail() {
        let data = Exporter.thumbnailJPEG(chart, maxDimension: 200)
        XCTAssertNotNil(data)
        let properties = readProperties(data ?? Data())
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth as String] as? Int, 200)
    }
}
