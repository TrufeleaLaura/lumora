import Foundation

/// Lipstick finish.
public enum LipFinish: String, CaseIterable, Codable, Sendable, Identifiable {
    case matte, satin, gloss, shimmer

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// A makeup color in sRGB (0...1), stored so documents are self-contained.
public struct MakeupColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// OKLab (L, a, b) of this color.
    public var oklab: (Double, Double, Double) {
        ColorMath.linearSRGBToOklab(ColorMath.srgbToLinear(red), ColorMath.srgbToLinear(green), ColorMath.srgbToLinear(blue))
    }
}

/// Curated palettes for the makeup tools.
public enum MakeupPalette {
    public static let lipstick: [(String, MakeupColor)] = [
        ("Nude", MakeupColor(0.78, 0.52, 0.47)),
        ("Rose", MakeupColor(0.80, 0.40, 0.48)),
        ("Coral", MakeupColor(0.93, 0.42, 0.36)),
        ("Classic red", MakeupColor(0.75, 0.08, 0.14)),
        ("Berry", MakeupColor(0.55, 0.12, 0.30)),
        ("Plum", MakeupColor(0.42, 0.15, 0.28)),
        ("Pink", MakeupColor(0.92, 0.45, 0.62)),
        ("Brick", MakeupColor(0.62, 0.24, 0.18)),
    ]

    public static let blush: [(String, MakeupColor)] = [
        ("Peach", MakeupColor(0.98, 0.62, 0.50)),
        ("Pink", MakeupColor(0.96, 0.55, 0.62)),
        ("Rose", MakeupColor(0.85, 0.45, 0.50)),
        ("Bronze", MakeupColor(0.75, 0.48, 0.32)),
    ]

    public static let eyeshadow: [(String, MakeupColor)] = [
        ("Champagne", MakeupColor(0.88, 0.76, 0.60)),
        ("Bronze", MakeupColor(0.60, 0.40, 0.25)),
        ("Smoky", MakeupColor(0.25, 0.23, 0.25)),
        ("Rose gold", MakeupColor(0.80, 0.55, 0.50)),
        ("Plum", MakeupColor(0.45, 0.25, 0.40)),
        ("Navy", MakeupColor(0.18, 0.22, 0.40)),
    ]

    public static let brows: [(String, MakeupColor)] = [
        ("Black", MakeupColor(0.08, 0.07, 0.07)),
        ("Dark brown", MakeupColor(0.22, 0.15, 0.11)),
        ("Brown", MakeupColor(0.36, 0.25, 0.17)),
        ("Taupe", MakeupColor(0.45, 0.38, 0.32)),
        ("Blonde", MakeupColor(0.66, 0.53, 0.36)),
        ("Auburn", MakeupColor(0.45, 0.22, 0.13)),
    ]

    public static let hair: [(String, MakeupColor)] = [
        ("Black", MakeupColor(0.06, 0.05, 0.05)),
        ("Espresso", MakeupColor(0.20, 0.13, 0.09)),
        ("Chestnut", MakeupColor(0.42, 0.24, 0.13)),
        ("Copper", MakeupColor(0.72, 0.34, 0.14)),
        ("Honey blonde", MakeupColor(0.82, 0.62, 0.36)),
        ("Platinum", MakeupColor(0.90, 0.88, 0.82)),
        ("Rose gold", MakeupColor(0.86, 0.56, 0.52)),
        ("Burgundy", MakeupColor(0.42, 0.10, 0.16)),
        ("Pastel pink", MakeupColor(0.96, 0.66, 0.78)),
        ("Ash blue", MakeupColor(0.50, 0.60, 0.72)),
    ]
}

/// Eyebrows, makeup and hair color for one face (0 = untouched).
public struct MakeupSettings: Codable, Hashable, Sendable {
    // Eyebrows
    /// 0...100 fuller brows.
    public var browThickness: Double = 0
    /// 0...100 darker / tinted.
    public var browColorAmount: Double = 0
    public var browColor = MakeupPalette.brows[1].1
    /// -100...100
    public var browLift: Double = 0
    public var browArch: Double = 0
    public var browTilt: Double = 0

    // Lips
    public var lipstickAmount: Double = 0
    public var lipstickColor = MakeupPalette.lipstick[1].1
    public var lipFinish = LipFinish.satin

    // Cheeks & contour
    public var blushAmount: Double = 0
    public var blushColor = MakeupPalette.blush[0].1
    public var contour: Double = 0
    public var highlight: Double = 0

    // Eyes
    public var eyeshadowAmount: Double = 0
    public var eyeshadowColor = MakeupPalette.eyeshadow[0].1
    public var eyeliner: Double = 0
    public var lashes: Double = 0

    // Hair
    public var hairColorAmount: Double = 0
    public var hairColor = MakeupPalette.hair[3].1

    public init() {}

    public var isIdentity: Bool { self == MakeupSettings() }

    /// Brow lift/arch/tilt need the warp stage.
    public var hasBrowShape: Bool { browLift != 0 || browArch != 0 || browTilt != 0 }
}
