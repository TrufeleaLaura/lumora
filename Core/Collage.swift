import Foundation

/// Canvas shapes for collages and stories.
public enum CollageAspect: String, Codable, CaseIterable, Sendable, Identifiable {
    case square, portrait, story, landscape

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .square: return "1:1"
        case .portrait: return "4:5"
        case .story: return "Story 9:16"
        case .landscape: return "16:9"
        }
    }

    /// Output size in pixels (Instagram-friendly).
    public var pixelSize: (width: Int, height: Int) {
        switch self {
        case .square: return (2160, 2160)
        case .portrait: return (2160, 2700)
        case .story: return (2160, 3840)
        case .landscape: return (3840, 2160)
        }
    }

    public var ratio: Double {
        let size = pixelSize
        return Double(size.width) / Double(size.height)
    }
}

/// Cell arrangements. Rects are in unit coordinates (0...1, y up).
public enum CollageLayout: String, Codable, CaseIterable, Sendable, Identifiable {
    case single, twoColumns, twoRows, threeLeft, threeTop, threeRows, four, six, moodboard

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .single: return "Single"
        case .twoColumns: return "Side by side"
        case .twoRows: return "Stacked"
        case .threeLeft: return "Feature left"
        case .threeTop: return "Feature top"
        case .threeRows: return "Three rows"
        case .four: return "Grid 4"
        case .six: return "Grid 6"
        case .moodboard: return "Moodboard"
        }
    }

    public var cells: [CGRectValue] {
        func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRectValue { CGRectValue(x: x, y: y, width: w, height: h) }
        let third = 1.0 / 3
        switch self {
        case .single: return [r(0, 0, 1, 1)]
        case .twoColumns: return [r(0, 0, 0.5, 1), r(0.5, 0, 0.5, 1)]
        case .twoRows: return [r(0, 0.5, 1, 0.5), r(0, 0, 1, 0.5)]
        case .threeLeft: return [r(0, 0, 0.6, 1), r(0.6, 0.5, 0.4, 0.5), r(0.6, 0, 0.4, 0.5)]
        case .threeTop: return [r(0, 0.4, 1, 0.6), r(0, 0, 0.5, 0.4), r(0.5, 0, 0.5, 0.4)]
        case .threeRows: return [r(0, 2 * third, 1, third), r(0, third, 1, third), r(0, 0, 1, third)]
        case .four: return [r(0, 0.5, 0.5, 0.5), r(0.5, 0.5, 0.5, 0.5), r(0, 0, 0.5, 0.5), r(0.5, 0, 0.5, 0.5)]
        case .six: return [r(0, 2 * third, 0.5, third), r(0.5, 2 * third, 0.5, third), r(0, third, 0.5, third), r(0.5, third, 0.5, third), r(0, 0, 0.5, third), r(0.5, 0, 0.5, third)]
        case .moodboard:
            return [r(0, 0.45, 0.58, 0.55), r(0.58, 0.62, 0.42, 0.38), r(0.58, 0.3, 0.42, 0.32), r(0, 0, 0.32, 0.45), r(0.32, 0, 0.26, 0.45), r(0.58, 0, 0.42, 0.3)]
        }
    }
}

/// How one photo sits in its cell: zoom (≥ 1) and offset (fractions of the cell size).
public struct CollageCrop: Codable, Equatable, Sendable {
    public var zoom: Double = 1
    public var offset = SIMD2<Double>(0, 0)

    public init() {}
}

public struct CollageSettings: Codable, Equatable, Sendable {
    public var layout: CollageLayout = .twoColumns
    public var aspect: CollageAspect = .portrait
    /// 0...100
    public var spacing: Double = 30
    public var margin: Double = 30
    public var cornerRadius: Double = 0
    public var background: RGBColor = .cream

    public init() {}

    /// Cell rectangles in pixels (y up) for a canvas of `width × height`.
    public func cellRects(width: Double, height: Double) -> [CGRectValue] {
        let short = min(width, height)
        let gap = short * 0.04 * spacing / 100
        let outer = short * 0.08 * margin / 100
        let areaWidth = width - 2 * outer
        let areaHeight = height - 2 * outer
        return layout.cells.map { cell in
            let x = outer + cell.x * areaWidth + gap / 2
            let y = outer + cell.y * areaHeight + gap / 2
            return CGRectValue(x: x, y: y, width: max(1, cell.width * areaWidth - gap), height: max(1, cell.height * areaHeight - gap))
        }
    }

    public func cornerRadius(width: Double, height: Double) -> Double {
        min(width, height) * 0.06 * cornerRadius / 100
    }
}

public enum CollageMath {
    /// The image rectangle (pixels, y up) that aspect-fills `cell` with `crop` applied.
    /// The result always covers the cell.
    public static func imageRect(imageWidth: Double, imageHeight: Double, cell: CGRectValue, crop: CollageCrop) -> CGRectValue {
        guard imageWidth > 0, imageHeight > 0 else { return cell }
        let fill = max(cell.width / imageWidth, cell.height / imageHeight) * max(crop.zoom, 1)
        let w = imageWidth * fill, h = imageHeight * fill
        // Offsets can move the image only as far as it still covers the cell.
        let maxX = (w - cell.width) / 2, maxY = (h - cell.height) / 2
        let dx = min(max(crop.offset.x * cell.width, -maxX), maxX)
        let dy = min(max(crop.offset.y * cell.height, -maxY), maxY)
        return CGRectValue(x: cell.midX - w / 2 + dx, y: cell.midY - h / 2 + dy, width: w, height: h)
    }
}
