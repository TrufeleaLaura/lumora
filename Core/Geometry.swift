import Foundation

/// Crop aspect ratio presets.
public enum AspectRatioPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case free, original, square
    case portrait4x5, portrait2x3, portrait3x4, portrait9x16
    case landscape5x4, landscape3x2, landscape4x3, landscape16x9

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .free: return "Free"
        case .original: return "Original"
        case .square: return "1:1"
        case .portrait4x5: return "4:5"
        case .portrait2x3: return "2:3"
        case .portrait3x4: return "3:4"
        case .portrait9x16: return "9:16"
        case .landscape5x4: return "5:4"
        case .landscape3x2: return "3:2"
        case .landscape4x3: return "4:3"
        case .landscape16x9: return "16:9"
        }
    }

    /// The same ratio turned 90° (4:5 ↔ 5:4); used when the photo is rotated.
    public var rotated: AspectRatioPreset {
        switch self {
        case .portrait4x5: return .landscape5x4
        case .landscape5x4: return .portrait4x5
        case .portrait2x3: return .landscape3x2
        case .landscape3x2: return .portrait2x3
        case .portrait3x4: return .landscape4x3
        case .landscape4x3: return .portrait3x4
        case .portrait9x16: return .landscape16x9
        case .landscape16x9: return .portrait9x16
        case .free, .original, .square: return self
        }
    }

    /// Width / height, or nil for free. `original` uses the photo's own ratio.
    public func ratio(originalWidth: Double, originalHeight: Double) -> Double? {
        switch self {
        case .free: return nil
        case .original: return originalHeight > 0 ? originalWidth / originalHeight : nil
        case .square: return 1
        case .portrait4x5: return 4.0 / 5.0
        case .portrait2x3: return 2.0 / 3.0
        case .portrait3x4: return 3.0 / 4.0
        case .portrait9x16: return 9.0 / 16.0
        case .landscape5x4: return 5.0 / 4.0
        case .landscape3x2: return 3.0 / 2.0
        case .landscape4x3: return 4.0 / 3.0
        case .landscape16x9: return 16.0 / 9.0
        }
    }
}

/// Normalized crop rectangle (0...1) inside the rotated/straightened photo.
/// Origin is the bottom-left corner (Core Image convention).
public struct CropRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = CropRect(x: 0, y: 0, width: 1, height: 1)

    public var isFull: Bool {
        abs(x) < 1e-6 && abs(y) < 1e-6 && abs(width - 1) < 1e-6 && abs(height - 1) < 1e-6
    }

    /// Clamped into the unit square with a minimum size.
    public func clamped(minimumSize: Double = 0.05) -> CropRect {
        let w = min(max(width, minimumSize), 1)
        let h = min(max(height, minimumSize), 1)
        return CropRect(x: min(max(x, 0), 1 - w), y: min(max(y, 0), 1 - h), width: w, height: h)
    }
}

/// Crop, rotation, flips, straightening and perspective.
public struct GeometrySettings: Codable, Equatable, Sendable {
    /// Clockwise quarter turns, 0...3.
    public var quarterTurns: Int = 0
    public var flipHorizontal = false
    public var flipVertical = false
    /// Degrees, -45...+45.
    public var straighten: Double = 0
    /// -100...+100: positive widens the top (fixes buildings leaning in).
    public var vertical: Double = 0
    /// -100...+100: positive widens the right side.
    public var horizontal: Double = 0
    public var crop = CropRect.full
    public var aspect = AspectRatioPreset.free

    public init() {}

    public var isIdentity: Bool {
        quarterTurns % 4 == 0 && !flipHorizontal && !flipVertical && straighten == 0
            && vertical == 0 && horizontal == 0 && crop.isFull
    }
}

public enum GeometryMath {
    /// Scale needed so an image rotated by `degrees` still covers its original frame (no empty corners).
    public static func coverScale(width: Double, height: Double, degrees: Double) -> Double {
        let theta = abs(degrees) * .pi / 180
        guard theta > 1e-9, width > 0, height > 0 else { return 1 }
        let c = cos(theta), s = sin(theta)
        return max((width * c + height * s) / width, (width * s + height * c) / height)
    }

    /// Largest crop of the given pixel aspect ratio, centered on `around` (normalized), inside the unit square.
    public static func crop(aspect ratio: Double, imageWidth: Double, imageHeight: Double, around: CropRect = .full) -> CropRect {
        guard ratio > 0, imageWidth > 0, imageHeight > 0 else { return around }
        // In normalized units, width/height must equal ratio * imageHeight / imageWidth.
        let normalizedRatio = ratio * imageHeight / imageWidth
        let centerX = around.x + around.width / 2
        let centerY = around.y + around.height / 2
        var width = around.width
        var height = width / normalizedRatio
        if height > around.height {
            height = around.height
            width = height * normalizedRatio
        }
        // Grow to the largest size that fits the image if `around` was full.
        let maxWidth = min(1, normalizedRatio)
        let maxHeight = maxWidth / normalizedRatio
        if around.isFull {
            width = maxWidth
            height = maxHeight
        }
        return CropRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height).clamped(minimumSize: 0.01)
    }

    /// Projective map from the unit square to a quad (Heckbert's closed form).
    /// Corners map as (0,0)→p0, (1,0)→p1, (1,1)→p2, (0,1)→p3. Returns rows (a,b,c), (d,e,f), (g,h,1):
    /// x = (a·u + b·v + c) / (g·u + h·v + 1), y = (d·u + e·v + f) / (g·u + h·v + 1).
    public static func homography(
        _ p0: (Double, Double), _ p1: (Double, Double), _ p2: (Double, Double), _ p3: (Double, Double)
    ) -> (x: (Double, Double, Double), y: (Double, Double, Double), w: (Double, Double, Double)) {
        let dx1 = p1.0 - p2.0, dx2 = p3.0 - p2.0, dx3 = p0.0 - p1.0 + p2.0 - p3.0
        let dy1 = p1.1 - p2.1, dy2 = p3.1 - p2.1, dy3 = p0.1 - p1.1 + p2.1 - p3.1
        var g = 0.0, h = 0.0
        if abs(dx3) > 1e-12 || abs(dy3) > 1e-12 {
            let det = dx1 * dy2 - dx2 * dy1
            if abs(det) > 1e-12 {
                g = (dx3 * dy2 - dx2 * dy3) / det
                h = (dx1 * dy3 - dx3 * dy1) / det
            }
        }
        let a = p1.0 - p0.0 + g * p1.0
        let b = p3.0 - p0.0 + h * p3.0
        let c = p0.0
        let d = p1.1 - p0.1 + g * p1.1
        let e = p3.1 - p0.1 + h * p3.1
        let f = p0.1
        return ((a, b, c), (d, e, f), (g, h, 1))
    }

    /// Applies a homography from `homography(_:_:_:_:)` to (u, v).
    public static func apply(_ m: (x: (Double, Double, Double), y: (Double, Double, Double), w: (Double, Double, Double)), u: Double, v: Double) -> (Double, Double) {
        let w = m.w.0 * u + m.w.1 * v + m.w.2
        return ((m.x.0 * u + m.x.1 * v + m.x.2) / w, (m.y.0 * u + m.y.1 * v + m.y.2) / w)
    }

    /// Output pixel size of an image after quarter turns.
    public static func rotatedSize(width: Double, height: Double, quarterTurns: Int) -> (Double, Double) {
        quarterTurns % 2 == 0 ? (width, height) : (height, width)
    }
}
