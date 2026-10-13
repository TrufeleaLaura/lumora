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
        ("Soft black", MakeupColor(0.12, 0.10, 0.10)),
        ("Espresso", MakeupColor(0.20, 0.13, 0.09)),
        ("Chocolate", MakeupColor(0.30, 0.18, 0.11)),
        ("Chestnut", MakeupColor(0.42, 0.24, 0.13)),
        ("Caramel", MakeupColor(0.62, 0.40, 0.22)),
        ("Honey blonde", MakeupColor(0.82, 0.62, 0.36)),
        ("Golden blonde", MakeupColor(0.88, 0.72, 0.42)),
        ("Ash blonde", MakeupColor(0.78, 0.72, 0.60)),
        ("Platinum", MakeupColor(0.90, 0.88, 0.82)),
        ("Strawberry", MakeupColor(0.85, 0.55, 0.38)),
        ("Copper", MakeupColor(0.72, 0.34, 0.14)),
        ("Auburn", MakeupColor(0.50, 0.20, 0.12)),
        ("Cherry red", MakeupColor(0.62, 0.08, 0.12)),
        ("Burgundy", MakeupColor(0.42, 0.10, 0.16)),
        ("Rose gold", MakeupColor(0.86, 0.56, 0.52)),
        ("Pastel pink", MakeupColor(0.96, 0.66, 0.78)),
        ("Lavender", MakeupColor(0.72, 0.62, 0.88)),
        ("Silver", MakeupColor(0.78, 0.79, 0.82)),
        ("Ash blue", MakeupColor(0.50, 0.60, 0.72)),
        ("Teal", MakeupColor(0.20, 0.50, 0.52)),
    ]
}

/// One-tap complete makeup looks (they replace the makeup, keep hair and face shape).
public struct MakeupLook: Identifiable, Sendable {
    public let id: String
    public let title: String
    let build: @Sendable (inout MakeupSettings, inout SkinTouch) -> Void

    /// Skin retouching that comes with a look.
    public struct SkinTouch: Sendable {
        public var smooth: Double = 0
        public var evenTone: Double = 0
    }

    /// Applies the look to a face's settings.
    public func apply(to settings: inout FaceRetouchSettings) {
        var makeup = MakeupSettings()
        // Hair and brow shape stay: they are not makeup.
        let old = settings.makeup
        makeup.hairColorAmount = old.hairColorAmount; makeup.hairColor = old.hairColor
        makeup.hairOmbre = old.hairOmbre; makeup.hairOmbreColor = old.hairOmbreColor
        makeup.hairShine = old.hairShine; makeup.hairVolume = old.hairVolume
        makeup.browLift = old.browLift; makeup.browArch = old.browArch; makeup.browTilt = old.browTilt
        var skin = SkinTouch(smooth: settings.smooth, evenTone: settings.evenTone)
        build(&makeup, &skin)
        settings.makeup = makeup
        settings.smooth = max(settings.smooth, skin.smooth)
        settings.evenTone = max(settings.evenTone, skin.evenTone)
    }

    private static func color(_ palette: [(String, MakeupColor)], _ name: String) -> MakeupColor {
        palette.first { $0.0 == name }?.1 ?? palette[0].1
    }

    public static let all: [MakeupLook] = [
        MakeupLook(id: "none", title: "No makeup") { _, _ in },
        MakeupLook(id: "natural", title: "Natural") { m, _ in
            m.lipstickAmount = 30; m.lipstickColor = color(MakeupPalette.lipstick, "Nude"); m.lipFinish = .satin
            m.blushAmount = 20; m.blushColor = color(MakeupPalette.blush, "Peach")
            m.highlight = 15; m.lashes = 20; m.browThickness = 15
        },
        MakeupLook(id: "cleanGirl", title: "Clean girl") { m, skin in
            skin.smooth = 30; skin.evenTone = 25
            m.lipstickAmount = 25; m.lipstickColor = color(MakeupPalette.lipstick, "Nude"); m.lipFinish = .gloss
            m.blushAmount = 25; m.blushColor = color(MakeupPalette.blush, "Peach")
            m.highlight = 30; m.browThickness = 25; m.lashes = 25
        },
        MakeupLook(id: "softGlam", title: "Soft glam") { m, skin in
            skin.smooth = 35
            m.lipstickAmount = 45; m.lipstickColor = color(MakeupPalette.lipstick, "Rose"); m.lipFinish = .satin
            m.blushAmount = 30; m.blushColor = color(MakeupPalette.blush, "Rose")
            m.contour = 30; m.highlight = 35
            m.eyeshadowAmount = 35; m.eyeshadowColor = color(MakeupPalette.eyeshadow, "Champagne")
            m.eyeliner = 30; m.lashes = 45; m.browThickness = 35; m.browColorAmount = 30
        },
        MakeupLook(id: "glassSkin", title: "Glass skin") { m, skin in
            skin.smooth = 45; skin.evenTone = 40
            m.lipstickAmount = 35; m.lipstickColor = color(MakeupPalette.lipstick, "Pink"); m.lipFinish = .gloss
            m.blushAmount = 25; m.blushColor = color(MakeupPalette.blush, "Pink")
            m.highlight = 45; m.lashes = 20; m.browThickness = 20
        },
        MakeupLook(id: "coquette", title: "Coquette") { m, skin in
            skin.smooth = 30
            m.lipstickAmount = 45; m.lipstickColor = color(MakeupPalette.lipstick, "Pink"); m.lipFinish = .gloss
            m.blushAmount = 40; m.blushColor = color(MakeupPalette.blush, "Pink")
            m.highlight = 30; m.eyeshadowAmount = 25; m.eyeshadowColor = color(MakeupPalette.eyeshadow, "Rose gold")
            m.lashes = 40
        },
        MakeupLook(id: "bronzed", title: "Bronzed") { m, _ in
            m.blushAmount = 35; m.blushColor = color(MakeupPalette.blush, "Bronze")
            m.contour = 40; m.highlight = 35
            m.eyeshadowAmount = 40; m.eyeshadowColor = color(MakeupPalette.eyeshadow, "Bronze")
            m.lipstickAmount = 35; m.lipstickColor = color(MakeupPalette.lipstick, "Brick"); m.lipFinish = .satin
            m.lashes = 35
        },
        MakeupLook(id: "boldRed", title: "Bold red") { m, skin in
            skin.smooth = 30
            m.lipstickAmount = 70; m.lipstickColor = color(MakeupPalette.lipstick, "Classic red"); m.lipFinish = .matte
            m.eyeliner = 50; m.lashes = 50; m.contour = 20; m.highlight = 20; m.browThickness = 30
        },
        MakeupLook(id: "smoky", title: "Smoky night") { m, _ in
            m.eyeshadowAmount = 60; m.eyeshadowColor = color(MakeupPalette.eyeshadow, "Smoky")
            m.eyeliner = 60; m.lashes = 60
            m.lipstickAmount = 35; m.lipstickColor = color(MakeupPalette.lipstick, "Nude"); m.lipFinish = .satin
            m.contour = 35; m.highlight = 25
        },
        MakeupLook(id: "berry", title: "Berry") { m, _ in
            m.lipstickAmount = 60; m.lipstickColor = color(MakeupPalette.lipstick, "Berry"); m.lipFinish = .matte
            m.eyeshadowAmount = 30; m.eyeshadowColor = color(MakeupPalette.eyeshadow, "Plum")
            m.blushAmount = 20; m.blushColor = color(MakeupPalette.blush, "Rose")
            m.eyeliner = 30; m.lashes = 30
        },
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
    public var hairColor = MakeupPalette.hair[4].1
    /// Ombré / balayage: the lengths fade into a second color (0...100).
    public var hairOmbre: Double = 0
    public var hairOmbreColor = MakeupPalette.hair[7].1
    /// Glossy shine (0...100).
    public var hairShine: Double = 0
    /// Fuller (+) or flatter (−) hair around the head (-100...100).
    public var hairVolume: Double = 0

    public init() {}

    public var isIdentity: Bool { self == MakeupSettings() }

    /// Brow lift/arch/tilt need the warp stage.
    public var hasBrowShape: Bool { browLift != 0 || browArch != 0 || browTilt != 0 }
}
