import Foundation

/// The parameters a look applies on top of the user's own adjustments.
public struct LookRecipe: Codable, Equatable, Sendable {
    public var light = LightSettings()
    public var color = ColorSettings()
    public var mixer = ColorMixerSettings()
    public var grading = ColorGradingSettings()
    public var blackWhite = BlackWhiteSettings()
    public var curve = ToneCurveSettings()
    /// 0...100
    public var fade: Double = 0
    /// 0...100
    public var grain: Double = 0
    /// -100...0
    public var vignette: Double = 0

    public init() {}

    // MARK: Builder helpers

    public mutating func mix(_ band: HueBand, hue: Double = 0, saturation: Double = 0, luminance: Double = 0) {
        mixer.hue[band.rawValue] = hue
        mixer.saturation[band.rawValue] = saturation
        mixer.luminance[band.rawValue] = luminance
    }

    public mutating func shadows(_ hue: Double, _ saturation: Double, luminance: Double = 0) {
        grading.shadows = GradingWheel(hue: hue, saturation: saturation, luminance: luminance)
    }

    public mutating func midtones(_ hue: Double, _ saturation: Double, luminance: Double = 0) {
        grading.midtones = GradingWheel(hue: hue, saturation: saturation, luminance: luminance)
    }

    public mutating func highlights(_ hue: Double, _ saturation: Double, luminance: Double = 0) {
        grading.highlights = GradingWheel(hue: hue, saturation: saturation, luminance: luminance)
    }

    public mutating func blackAndWhite(_ mix: [HueBand: Double] = [:]) {
        blackWhite.isEnabled = true
        for (band, value) in mix {
            blackWhite.mix[band.rawValue] = value
        }
    }
}

public enum CurveShape {
    /// Lifted blacks and softened whites (film "matte").
    public static func matte(black: Double, white: Double = 1) -> [CurvePoint] {
        [
            CurvePoint(x: 0, y: black),
            CurvePoint(x: 0.18, y: 0.18 + black * 0.45),
            CurvePoint(x: 0.82, y: 0.82 - (1 - white) * 0.4),
            CurvePoint(x: 1, y: white),
        ]
    }

    /// Classic S-curve; `strength` ~0.02...0.08.
    public static func s(_ strength: Double, black: Double = 0) -> [CurvePoint] {
        [
            CurvePoint(x: 0, y: black),
            CurvePoint(x: 0.25, y: 0.25 - strength + black * 0.5),
            CurvePoint(x: 0.75, y: 0.75 + strength),
            CurvePoint(x: 1, y: 1),
        ]
    }
}

public enum LookPack: String, CaseIterable, Codable, Sendable, Identifiable {
    case trending, essentials, film, portrait, bright, moody, vintage, blackAndWhite, landscape, custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .trending: return "Trending"
        case .essentials: return "Essentials"
        case .film: return "Film"
        case .portrait: return "Portrait"
        case .bright: return "Bright & Airy"
        case .moody: return "Moody"
        case .vintage: return "Vintage"
        case .blackAndWhite: return "B&W"
        case .landscape: return "Landscape"
        case .custom: return "My looks"
        }
    }
}

public struct Look: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let pack: LookPack
    public let recipe: LookRecipe
    /// For looks made from an imported .cube LUT.
    public let lutID: String?

    public init(id: String, name: String, pack: LookPack, recipe: LookRecipe, lutID: String? = nil) {
        self.id = id
        self.name = name
        self.pack = pack
        self.recipe = recipe
        self.lutID = lutID
    }

    init(_ pack: LookPack, _ name: String, _ build: (inout LookRecipe) -> Void) {
        var recipe = LookRecipe()
        build(&recipe)
        self.init(
            id: "\(pack.rawValue).\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
            name: name,
            pack: pack,
            recipe: recipe
        )
    }
}

/// The selected look and its strength, stored in the edit document. The recipe is copied in,
/// so a saved edit keeps its appearance even if the built-in library changes later.
public struct LookSettings: Codable, Equatable, Sendable {
    public var lookID: String?
    public var name: String?
    public var recipe: LookRecipe?
    /// Imported LUT applied by this look (see LUTStore), if any.
    public var lutID: String?
    /// 0...100
    public var amount: Double = 100

    public init(lookID: String? = nil, name: String? = nil, recipe: LookRecipe? = nil, lutID: String? = nil, amount: Double = 100) {
        self.lookID = lookID
        self.name = name
        self.recipe = recipe
        self.lutID = lutID
        self.amount = amount
    }

    public init(look: Look, amount: Double = 100) {
        self.init(lookID: look.id, name: look.name, recipe: look.recipe, lutID: look.lutID, amount: amount)
    }

    public var isActive: Bool {
        lookID != nil && amount > 0 && (recipe != nil || lutID != nil)
    }
}

/// Built-in looks. Hue angles: 0 red, 30 orange, 60 yellow, 120 green, 180 cyan, 220 blue, 300 magenta.
public enum LookLibrary {
    public static let all: [Look] = trending + essentials + film + portrait + bright + moody + vintage + blackAndWhite + landscape

    public static func look(id: String) -> Look? {
        all.first { $0.id == id }
    }

    public static func looks(in pack: LookPack) -> [Look] {
        all.filter { $0.pack == pack }
    }

    /// Current favourites for portraits and social feeds.
    static let trending: [Look] = [
        Look(.trending, "Clean Girl") { r in
            r.light.exposure = 0.1; r.light.contrast = -8; r.light.highlights = -10; r.light.shadows = 12
            r.color.temperature = 8; r.color.vibrance = 8; r.color.saturation = -5
            r.mix(.orange, luminance: 8); r.fade = 5
        },
        Look(.trending, "Latte") { r in
            r.light.contrast = -5; r.color.temperature = 18; r.color.tint = 4; r.color.saturation = -12
            r.mix(.orange, hue: 5); r.shadows(30, 12); r.highlights(45, 10); r.fade = 12
        },
        Look(.trending, "Mocha") { r in
            r.light.exposure = -0.1; r.light.contrast = 10; r.color.temperature = 12; r.color.saturation = -18
            r.shadows(25, 20, luminance: -5); r.mix(.blue, saturation: -40); r.fade = 8
        },
        Look(.trending, "Soft Pink") { r in
            r.light.exposure = 0.1; r.light.contrast = -10; r.color.tint = 8; r.color.saturation = -5
            r.highlights(340, 12); r.mix(.red, luminance: 10); r.mix(.magenta, luminance: 10); r.fade = 10
        },
        Look(.trending, "Coquette") { r in
            r.light.contrast = -12; r.color.tint = 10; r.color.temperature = 6
            r.highlights(350, 15); r.shadows(330, 8); r.fade = 15; r.grain = 10
        },
        Look(.trending, "Cinematic") { r in
            r.light.contrast = 15; r.color.saturation = -5
            r.shadows(200, 25); r.highlights(35, 20); r.curve.master = CurveShape.matte(black: 0.04); r.vignette = -15
        },
        Look(.trending, "Flash") { r in
            r.light.exposure = 0.25; r.light.contrast = 25; r.light.whites = 20; r.light.blacks = -15; r.light.highlights = -5
            r.color.saturation = 5; r.vignette = -25; r.grain = 20
        },
        Look(.trending, "Portra") { r in
            r.light.contrast = -6; r.light.highlights = -15; r.light.shadows = 10; r.color.temperature = 6; r.color.tint = 4
            r.mix(.green, hue: 15, saturation: -15); r.mix(.orange, saturation: -5, luminance: 6)
            r.highlights(45, 10); r.shadows(200, 6); r.fade = 8; r.grain = 20
        },
        Look(.trending, "Y2K") { r in
            r.light.contrast = 18; r.color.tint = 12; r.color.temperature = -8; r.color.saturation = 15
            r.highlights(300, 10); r.shadows(190, 15); r.grain = 15; r.vignette = -10
        },
        Look(.trending, "Golden Glow") { r in
            r.light.exposure = 0.1; r.light.highlights = -20; r.color.temperature = 25; r.color.tint = 6
            r.color.vibrance = 15; r.highlights(40, 18)
        },
        Look(.trending, "Matte") { r in
            r.light.contrast = -10; r.color.saturation = -10; r.fade = 20; r.curve.master = CurveShape.matte(black: 0.06)
        },
        Look(.trending, "Retro Film") { r in
            r.color.temperature = 10; r.color.saturation = -15; r.shadows(190, 12); r.highlights(50, 12)
            r.fade = 15; r.grain = 30; r.vignette = -20
        },
        Look(.trending, "Clean Bright") { r in
            r.light.exposure = 0.2; r.light.whites = 15; r.light.highlights = -20; r.light.shadows = 15
            r.color.vibrance = 10; r.color.temperature = 3
        },
        Look(.trending, "Moody Brown") { r in
            r.light.exposure = -0.15; r.light.contrast = 15; r.color.temperature = 15; r.color.saturation = -20
            r.mix(.green, saturation: -50); r.mix(.blue, saturation: -40); r.shadows(30, 15)
        },
    ]

    static let essentials: [Look] = [
        Look(.essentials, "Vivid") { r in
            r.light.contrast = 15; r.color.vibrance = 30; r.color.saturation = 5
            r.curve.master = CurveShape.s(0.03)
        },
        Look(.essentials, "Natural") { r in
            r.light.contrast = 6; r.light.highlights = -12; r.light.shadows = 10; r.color.vibrance = 12
        },
        Look(.essentials, "Crisp") { r in
            r.light.contrast = 22; r.light.whites = 10; r.light.blacks = -12; r.color.vibrance = 10
        },
        Look(.essentials, "Soft") { r in
            r.light.contrast = -15; r.light.highlights = -12; r.color.saturation = -6
            r.curve.master = CurveShape.matte(black: 0.03)
        },
        Look(.essentials, "Warm") { r in
            r.color.temperature = 16; r.color.tint = 3; r.color.vibrance = 8
        },
        Look(.essentials, "Cool") { r in
            r.color.temperature = -16; r.color.tint = -2; r.shadows(220, 10)
        },
        Look(.essentials, "Punch") { r in
            r.light.contrast = 28; r.color.saturation = 15; r.light.blacks = -10
            r.curve.master = CurveShape.s(0.05)
        },
        Look(.essentials, "Matte") { r in
            r.light.contrast = -5; r.color.saturation = -10
            r.curve.master = CurveShape.matte(black: 0.08, white: 0.95)
        },
    ]

    static let film: [Look] = [
        Look(.film, "Portra Soft") { r in
            r.light.contrast = -10; r.light.highlights = -15; r.light.shadows = 10
            r.color.temperature = 6; r.color.vibrance = -5; r.color.saturation = -8
            r.mix(.orange, saturation: -10, luminance: 8); r.mix(.green, hue: -20, saturation: -25); r.mix(.blue, saturation: -15)
            r.shadows(30, 8); r.highlights(40, 10)
            r.curve.master = CurveShape.matte(black: 0.05, white: 0.97)
            r.fade = 6; r.grain = 15
        },
        Look(.film, "Ektar Pop") { r in
            r.light.contrast = 15; r.color.saturation = 18
            r.mix(.red, saturation: 15); r.mix(.orange, saturation: -5); r.mix(.green, hue: -10); r.mix(.blue, saturation: 20, luminance: -10)
            r.shadows(220, 8)
            r.curve.master = CurveShape.s(0.03)
        },
        Look(.film, "Gold 200") { r in
            r.color.temperature = 18; r.color.tint = 4
            r.mix(.yellow, saturation: 10); r.mix(.blue, saturation: -15)
            r.shadows(25, 10); r.highlights(45, 22)
            r.fade = 6; r.grain = 18
        },
        Look(.film, "Fuji 400H") { r in
            r.light.contrast = -10; r.color.temperature = -4; r.color.tint = -5
            r.mix(.orange, saturation: -8, luminance: 8); r.mix(.green, hue: 25, saturation: -15, luminance: 10)
            r.mix(.aqua, saturation: -10); r.mix(.blue, saturation: -10)
            r.shadows(175, 10); r.highlights(340, 6)
            r.curve.master = CurveShape.matte(black: 0.05)
            r.grain = 15
        },
        Look(.film, "Superia") { r in
            r.light.contrast = 10; r.color.tint = -8
            r.mix(.red, saturation: 10); r.mix(.green, saturation: 10)
            r.shadows(140, 14); r.highlights(320, 8)
            r.grain = 22
        },
        Look(.film, "Cinestill 800T") { r in
            r.light.contrast = 10; r.color.temperature = -22; r.color.tint = 6
            r.mix(.red, hue: -5, saturation: 15); r.mix(.orange, hue: -8); r.mix(.blue, luminance: -10)
            r.shadows(205, 22); r.highlights(25, 18)
            r.curve.master = CurveShape.s(0.02)
            r.grain = 25
        },
        Look(.film, "Kodachrome") { r in
            r.light.contrast = 25; r.light.blacks = -10; r.color.saturation = 12
            r.mix(.red, saturation: 20, luminance: -10); r.mix(.yellow, saturation: 10)
            r.mix(.green, hue: -8, saturation: -10); r.mix(.blue, saturation: 15, luminance: -15)
            r.highlights(40, 10)
            r.curve.master = CurveShape.s(0.04)
        },
        Look(.film, "Polaroid") { r in
            r.light.contrast = -12; r.color.temperature = 6; r.color.saturation = -10
            r.shadows(185, 20); r.highlights(45, 18)
            r.curve.master = CurveShape.matte(black: 0.10, white: 0.92)
            r.fade = 22; r.vignette = -15; r.grain = 12
        },
        Look(.film, "Expired") { r in
            r.color.temperature = 10; r.color.tint = 12; r.color.saturation = -15
            r.shadows(160, 25); r.highlights(35, 25)
            r.curve.master = CurveShape.matte(black: 0.07, white: 0.95)
            r.fade = 18; r.grain = 35
        },
        Look(.film, "Velvia") { r in
            r.light.contrast = 20; r.color.saturation = 25; r.color.vibrance = 15
            r.mix(.red, saturation: 15); r.mix(.green, saturation: 20, luminance: -10); r.mix(.blue, saturation: 25, luminance: -15)
            r.shadows(230, 6)
        },
    ]

    static let portrait: [Look] = [
        Look(.portrait, "Peach Glow") { r in
            r.light.contrast = -5; r.light.highlights = -15; r.light.shadows = 10
            r.color.temperature = 8; r.color.tint = 5
            r.mix(.red, saturation: -8, luminance: 5); r.mix(.orange, hue: -6, saturation: -10, luminance: 12)
            r.highlights(30, 14)
            r.curve.master = CurveShape.matte(black: 0.03)
        },
        Look(.portrait, "Golden Hour") { r in
            r.color.temperature = 22; r.color.tint = 6; r.color.vibrance = 10
            r.mix(.orange, luminance: 8); r.mix(.yellow, saturation: 10)
            r.shadows(20, 12); r.highlights(40, 25)
        },
        Look(.portrait, "Soft Rose") { r in
            r.light.contrast = -10; r.color.tint = 10; r.color.saturation = -8
            r.shadows(330, 8); r.highlights(345, 12)
            r.curve.master = CurveShape.matte(black: 0.04)
        },
        Look(.portrait, "Clean Skin") { r in
            r.light.highlights = -10; r.light.shadows = 8; r.color.vibrance = 6
            r.mix(.red, saturation: -10, luminance: 6); r.mix(.orange, saturation: -12, luminance: 10)
        },
        Look(.portrait, "Bronze") { r in
            r.light.contrast = 12; r.color.temperature = 12
            r.mix(.red, luminance: -6); r.mix(.orange, saturation: 10, luminance: -8)
            r.shadows(25, 15); r.highlights(40, 10)
        },
        Look(.portrait, "Porcelain") { r in
            r.light.exposure = 0.15; r.light.contrast = -8; r.color.temperature = -5; r.color.saturation = -12
            r.mix(.red, saturation: -15, luminance: 10); r.mix(.orange, saturation: -20, luminance: 15)
            r.curve.master = CurveShape.matte(black: 0.03)
        },
    ]

    static let bright: [Look] = [
        Look(.bright, "Airy") { r in
            r.light.exposure = 0.3; r.light.contrast = -15; r.light.highlights = -20; r.light.shadows = 25
            r.color.temperature = 4; r.color.saturation = -10
            r.mix(.orange, luminance: 8)
            r.curve.master = CurveShape.matte(black: 0.05, white: 0.98)
        },
        Look(.bright, "Pastel") { r in
            r.light.contrast = -20; r.color.saturation = -15; r.color.vibrance = 5
            r.mix(.green, hue: 15, saturation: -20); r.mix(.blue, hue: -5, luminance: 10)
            r.shadows(190, 10); r.highlights(320, 8)
            r.fade = 10
        },
        Look(.bright, "Cream") { r in
            r.light.contrast = -10; r.color.temperature = 10; r.color.tint = 2; r.color.saturation = -12
            r.highlights(45, 14)
            r.fade = 12
        },
        Look(.bright, "Blush") { r in
            r.light.exposure = 0.15; r.color.tint = 12; r.color.temperature = 4; r.color.saturation = -6
            r.shadows(320, 6); r.highlights(350, 15)
        },
        Look(.bright, "Clean White") { r in
            r.light.exposure = 0.2; r.light.whites = 15; r.light.highlights = -10
            r.color.temperature = -6; r.color.saturation = -6
            r.mix(.yellow, saturation: -20)
        },
        Look(.bright, "Sunny") { r in
            r.light.exposure = 0.1; r.light.contrast = 5; r.color.temperature = 14; r.color.vibrance = 15
            r.highlights(50, 18)
        },
    ]

    static let moody: [Look] = [
        Look(.moody, "Dark Teal") { r in
            r.light.exposure = -0.25; r.light.contrast = 15; r.color.saturation = -10
            r.mix(.orange, saturation: -5); r.mix(.green, hue: 40, saturation: -30); r.mix(.aqua, saturation: 10); r.mix(.blue, hue: -10, saturation: -10)
            r.shadows(195, 25); r.midtones(190, 8); r.highlights(35, 10)
            r.curve.master = CurveShape.matte(black: 0.04)
        },
        Look(.moody, "Forest") { r in
            r.light.exposure = -0.2; r.light.contrast = 10
            r.mix(.yellow, hue: -20, saturation: -20); r.mix(.green, hue: -15, saturation: -25, luminance: -20)
            r.shadows(140, 15); r.highlights(40, 8)
            r.fade = 5
        },
        Look(.moody, "Noir Warm") { r in
            r.light.exposure = -0.3; r.light.contrast = 20; r.color.saturation = -30; r.color.temperature = 10
            r.shadows(25, 15)
            r.vignette = -25
        },
        Look(.moody, "Muted Earth") { r in
            r.light.contrast = -5; r.color.temperature = 8; r.color.saturation = -25
            r.mix(.orange, saturation: -5); r.mix(.green, saturation: -30); r.mix(.blue, saturation: -30)
            r.shadows(30, 10)
            r.curve.master = CurveShape.matte(black: 0.05)
        },
        Look(.moody, "Rainy Day") { r in
            r.light.contrast = -10; r.color.temperature = -12; r.color.saturation = -25
            r.shadows(215, 15); r.highlights(200, 5)
            r.fade = 8
        },
        Look(.moody, "Cinematic") { r in
            r.light.contrast = 12
            r.mix(.orange, saturation: 5, luminance: 5); r.mix(.green, hue: 30, saturation: -20); r.mix(.blue, hue: -10, saturation: 10)
            r.shadows(195, 30); r.highlights(30, 22)
            r.curve.master = CurveShape.s(0.03)
            r.vignette = -10
        },
    ]

    static let vintage: [Look] = [
        Look(.vintage, "70s") { r in
            r.color.temperature = 16; r.color.tint = 4; r.color.saturation = -5
            r.mix(.green, hue: -20, saturation: -15); r.mix(.blue, saturation: -20)
            r.shadows(20, 18); r.highlights(45, 20)
            r.fade = 15; r.grain = 20; r.vignette = -15
        },
        Look(.vintage, "90s Disposable") { r in
            r.light.exposure = 0.1; r.light.contrast = 15; r.color.tint = -6; r.color.saturation = 8
            r.shadows(160, 15); r.highlights(40, 12)
            r.grain = 30; r.vignette = -20
        },
        Look(.vintage, "Faded Memory") { r in
            r.light.contrast = -15; r.color.temperature = 6; r.color.saturation = -20
            r.shadows(200, 12)
            r.fade = 25; r.grain = 18
        },
        Look(.vintage, "Sepia Soft") { r in
            r.light.contrast = -5
            r.blackAndWhite()
            r.shadows(30, 28); r.highlights(45, 22)
            r.fade = 10; r.grain = 12
        },
        Look(.vintage, "Retro Warm") { r in
            r.light.contrast = 8; r.color.temperature = 20; r.color.saturation = -10
            r.mix(.green, hue: -15); r.mix(.blue, hue: -15, saturation: -25)
            r.curve.master = CurveShape.matte(black: 0.06)
            r.grain = 15
        },
        Look(.vintage, "Dusty Rose") { r in
            r.color.tint = 10; r.color.saturation = -18
            r.shadows(300, 8); r.highlights(350, 14)
            r.fade = 12
        },
        Look(.vintage, "Film Fade") { r in
            r.light.contrast = -10; r.color.saturation = -8
            r.curve.master = CurveShape.matte(black: 0.12, white: 0.93)
            r.grain = 20
        },
    ]

    static let blackAndWhite: [Look] = [
        Look(.blackAndWhite, "Classic") { r in
            r.blackAndWhite(); r.light.contrast = 10
            r.curve.master = CurveShape.s(0.02)
        },
        Look(.blackAndWhite, "High Contrast") { r in
            r.blackAndWhite([.red: 20, .blue: -20]); r.light.contrast = 40; r.light.blacks = -20; r.light.whites = 15
        },
        Look(.blackAndWhite, "Soft Matte") { r in
            r.blackAndWhite(); r.light.contrast = -15
            r.curve.master = CurveShape.matte(black: 0.08)
            r.grain = 10
        },
        Look(.blackAndWhite, "Selenium") { r in
            r.blackAndWhite(); r.light.contrast = 15
            r.shadows(230, 12); r.highlights(40, 6)
        },
        Look(.blackAndWhite, "Tri-X") { r in
            r.blackAndWhite([.orange: 10, .blue: -15]); r.light.contrast = 25
            r.curve.master = CurveShape.s(0.04)
            r.grain = 45
        },
        Look(.blackAndWhite, "Infrared") { r in
            r.blackAndWhite([.green: 100, .yellow: 80, .aqua: -40, .blue: -60]); r.light.contrast = 20
        },
    ]

    static let landscape: [Look] = [
        Look(.landscape, "Deep Sky") { r in
            r.light.contrast = 10; r.light.highlights = -25; r.color.vibrance = 12
            r.mix(.aqua, saturation: 10, luminance: -10); r.mix(.blue, saturation: 20, luminance: -25)
        },
        Look(.landscape, "Lush") { r in
            r.light.contrast = 8; r.color.vibrance = 15
            r.mix(.yellow, hue: -10, saturation: 15); r.mix(.green, hue: -5, saturation: 25, luminance: 5)
        },
        Look(.landscape, "Autumn") { r in
            r.color.temperature = 10
            r.mix(.red, saturation: 15); r.mix(.orange, saturation: 25); r.mix(.yellow, hue: -20, saturation: 15); r.mix(.green, hue: -30, saturation: -10)
        },
        Look(.landscape, "Desert") { r in
            r.light.contrast = 10; r.color.temperature = 15
            r.mix(.orange, saturation: 15, luminance: 5); r.mix(.blue, saturation: -10)
            r.highlights(40, 12)
        },
        Look(.landscape, "Alpine") { r in
            r.light.contrast = 12; r.light.highlights = -20; r.light.whites = 10; r.color.temperature = -8
            r.mix(.green, saturation: -10); r.mix(.blue, saturation: 15, luminance: -15)
        },
        Look(.landscape, "Ocean") { r in
            r.light.contrast = 8; r.color.temperature = -6; r.color.vibrance = 10
            r.mix(.aqua, hue: 5, saturation: 25); r.mix(.blue, saturation: 20)
        },
        Look(.landscape, "Sunset Glow") { r in
            r.color.temperature = 20; r.color.tint = 8
            r.mix(.red, saturation: 10); r.mix(.orange, saturation: 15); r.mix(.magenta, saturation: 10)
            r.shadows(280, 10); r.highlights(25, 20)
        },
    ]
}
