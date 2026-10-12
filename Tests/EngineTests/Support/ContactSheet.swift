import CoreImage
import CoreImage.CIFilterBuiltins
import XCTest
@testable import LumoraEngine

/// Builds labelled side-by-side "contact sheets" of render results and writes them as PNG.
/// CI uploads the output folder so results can be reviewed visually.
enum ContactSheet {
    static var outputDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["LUMORA_TEST_OUTPUT"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("lumora-render-output", isDirectory: true)
    }

    static func make(_ items: [(String, CIImage)], tileWidth: CGFloat = 360, columns: Int = 4) -> CIImage {
        let gap: CGFloat = 14
        let labelHeight: CGFloat = 34
        var composed = CIImage.empty()
        var rowHeights: [CGFloat] = []

        // Lay out row by row, top to bottom (Core Image's y axis points up, so rows are flipped at the end).
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
        var tiles: [(row: Int, column: Int, label: String, image: CIImage)] = []
        for (rowIndex, row) in rows.enumerated() {
            var height: CGFloat = 0
            for (columnIndex, item) in row.enumerated() {
                let extent = item.1.extent
                let scale = tileWidth / extent.width
                let scaled = item.1
                    .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
                    .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                height = max(height, scaled.extent.height)
                tiles.append((rowIndex, columnIndex, item.0, scaled))
            }
            rowHeights.append(height + labelHeight)
        }

        let totalHeight = rowHeights.reduce(gap) { $0 + $1 + gap }
        let totalWidth = gap + CGFloat(min(columns, max(items.count, 1))) * (tileWidth + gap)

        for tile in tiles {
            let x = gap + CGFloat(tile.column) * (tileWidth + gap)
            let rowTop = totalHeight - gap - rowHeights[0..<tile.row].reduce(0) { $0 + $1 + gap }
            let imageTop = rowTop - labelHeight
            let placed = tile.image.transformed(by: CGAffineTransform(translationX: x, y: imageTop - tile.image.extent.height))
            composed = placed.composited(over: composed)

            let text = CIFilter.textImageGenerator()
            text.text = tile.label
            text.fontName = "HelveticaNeue-Medium"
            text.fontSize = 20
            text.scaleFactor = 1
            if let label = text.outputImage {
                let positioned = label.transformed(by: CGAffineTransform(
                    translationX: x - label.extent.minX,
                    y: rowTop - labelHeight + 6 - label.extent.minY
                ))
                composed = positioned.composited(over: composed)
            }
        }

        let canvas = CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
        let background = CIImage(color: CIColor(red: 0.93, green: 0.93, blue: 0.93)).cropped(to: canvas)
        return composed.composited(over: background).cropped(to: canvas)
    }

    @discardableResult
    static func write(_ items: [(String, CIImage)], name: String, columns: Int = 4) throws -> URL {
        let sheet = make(items, columns: columns)
        let directory = outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).png")
        guard let data = RenderContext.shared.pngRepresentation(of: sheet, format: .RGBA8, colorSpace: RenderContext.sRGB, options: [:]) else {
            throw ExportError.encodingFailed(.png)
        }
        try data.write(to: url)

        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Contact sheet \(name)") { activity in
            activity.add(attachment)
        }
        return url
    }
}
