import Foundation

/// One-tap local edits (Lightroom "adaptive presets"): each creates masks with tuned
/// adjustments (or a few global changes), which can then be fine-tuned like any mask.
public struct MaskPreset: Identifiable, Sendable {
    public enum Category: String, CaseIterable, Identifiable, Sendable {
        case portrait, subject, background, sky, travel, body

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .portrait: return "Portrait"
            case .subject: return "Subject"
            case .background: return "Background"
            case .sky: return "Sky"
            case .travel: return "Travel"
            case .body: return "Body"
            }
        }

        public var symbol: String {
            switch self {
            case .portrait: return "face.smiling"
            case .subject: return "person.crop.rectangle"
            case .background: return "rectangle.dashed"
            case .sky: return "cloud.sun"
            case .travel: return "airplane"
            case .body: return "figure.stand"
            }
        }
    }

    public let id: String
    public let title: String
    public let category: Category
    /// The automatic mask the preset needs (to find it before applying), if any.
    public let needs: MaskKind?
    let make: @Sendable (inout EditDocument) -> Void

    /// Adds the preset to a document.
    public func apply(to document: inout EditDocument) {
        make(&document)
    }
}

public enum MaskPresetLibrary {
    private static func people(_ parts: [PersonPart]) -> MaskComponent {
        var component = MaskCatalog.component(.people)
        component.parts = parts
        return component
    }

    private static func mask(_ name: String, _ components: [MaskComponent], _ change: (inout LocalAdjustments) -> Void) -> Mask {
        var mask = Mask(name: name, components: components)
        change(&mask.adjustments)
        return mask
    }

    private static func preset(_ id: String, _ title: String, _ category: MaskPreset.Category, needs: MaskKind?, _ masks: @escaping @Sendable () -> [Mask]) -> MaskPreset {
        MaskPreset(id: id, title: title, category: category, needs: needs) { document in
            document.masks.append(contentsOf: masks())
        }
    }

    public static let all: [MaskPreset] = portrait + subject + background + sky + travel + body

    public static func presets(in category: MaskPreset.Category) -> [MaskPreset] {
        all.filter { $0.category == category }
    }

    // MARK: - Portrait

    static let portrait: [MaskPreset] = [
        preset("portrait.smooth", "Smooth skin", .portrait, needs: .people) {
            [mask("Smooth skin", [people([.faceSkin, .bodySkin])]) { $0.texture = -40; $0.clarity = -20; $0.sharpness = -10 }]
        },
        preset("portrait.glow", "Glowing skin", .portrait, needs: .people) {
            [mask("Glowing skin", [people([.faceSkin])]) { $0.exposure = 0.15; $0.highlights = 12; $0.texture = -20; $0.colorAmount = 8; $0.colorHue = 35 }]
        },
        preset("portrait.brighten", "Brighten face", .portrait, needs: .people) {
            [mask("Brighten face", [people([.faceSkin])]) { $0.exposure = 0.3; $0.shadows = 25 }]
        },
        preset("portrait.eyes", "Bright eyes", .portrait, needs: .people) {
            [mask("Bright eyes", [people([.eyes, .iris])]) { $0.exposure = 0.3; $0.clarity = 25; $0.sharpness = 25 }]
        },
        preset("portrait.teeth", "Whiten teeth", .portrait, needs: .people) {
            [mask("Whiten teeth", [people([.teeth])]) { $0.saturation = -45; $0.exposure = 0.2 }]
        },
        preset("portrait.brows", "Define brows", .portrait, needs: .people) {
            [mask("Define brows", [people([.brows])]) { $0.exposure = -0.25; $0.clarity = 20; $0.contrast = 10 }]
        },
        preset("portrait.lips", "Rosy lips", .portrait, needs: .people) {
            [mask("Rosy lips", [people([.lips])]) { $0.saturation = 25; $0.colorAmount = 25; $0.colorHue = 350 }]
        },
        preset("portrait.hairShine", "Shiny hair", .portrait, needs: .people) {
            [mask("Shiny hair", [people([.hair])]) { $0.texture = 25; $0.clarity = 15; $0.highlights = 15; $0.contrast = 10 }]
        },
        preset("portrait.hairDark", "Darker hair", .portrait, needs: .people) {
            [mask("Darker hair", [people([.hair])]) { $0.exposure = -0.35; $0.saturation = 10 }]
        },
        preset("portrait.hairWarm", "Warm hair", .portrait, needs: .people) {
            [mask("Warm hair", [people([.hair])]) { $0.temperature = 20; $0.colorAmount = 30; $0.colorHue = 30 }]
        },
    ]

    // MARK: - Subject

    static let subject: [MaskPreset] = [
        preset("subject.pop", "Pop", .subject, needs: .subject) {
            [mask("Pop", [MaskCatalog.component(.subject)]) { $0.exposure = 0.15; $0.clarity = 20; $0.texture = 10; $0.saturation = 15 }]
        },
        preset("subject.warmPop", "Warm pop", .subject, needs: .subject) {
            [mask("Warm pop", [MaskCatalog.component(.subject)]) { $0.exposure = 0.1; $0.temperature = 15; $0.saturation = 12; $0.clarity = 12 }]
        },
        preset("subject.soft", "Soft", .subject, needs: .subject) {
            [mask("Soft", [MaskCatalog.component(.subject)]) { $0.clarity = -20; $0.texture = -15; $0.highlights = -15 }]
        },
        preset("subject.coolSoft", "Cool soft", .subject, needs: .subject) {
            [mask("Cool soft", [MaskCatalog.component(.subject)]) { $0.temperature = -12; $0.clarity = -15; $0.saturation = -5 }]
        },
        preset("subject.spotlight", "Spotlight", .subject, needs: .subject) {
            [
                mask("Spotlight subject", [MaskCatalog.component(.subject)]) { $0.exposure = 0.2; $0.clarity = 10 },
                mask("Spotlight background", [MaskCatalog.component(.background)]) { $0.exposure = -0.6; $0.saturation = -20 },
            ]
        },
    ]

    // MARK: - Background

    static let background: [MaskPreset] = [
        preset("background.darken", "Darken", .background, needs: .subject) {
            [mask("Darker background", [MaskCatalog.component(.background)]) { $0.exposure = -0.6; $0.highlights = -20 }]
        },
        preset("background.mute", "Mute colors", .background, needs: .subject) {
            [mask("Muted background", [MaskCatalog.component(.background)]) { $0.saturation = -65 }]
        },
        MaskPreset(id: "background.blur", title: "Blur", category: .background, needs: .subject) { document in
            document.styles.lensBlur.mode = .subject
            document.styles.lensBlur.amount = max(document.styles.lensBlur.amount, 65)
        },
        preset("background.warm", "Warm", .background, needs: .subject) {
            [mask("Warm background", [MaskCatalog.component(.background)]) { $0.temperature = 25; $0.saturation = 10 }]
        },
        preset("background.cool", "Cool", .background, needs: .subject) {
            [mask("Cool background", [MaskCatalog.component(.background)]) { $0.temperature = -25; $0.tint = 5 }]
        },
        preset("background.dreamy", "Dreamy", .background, needs: .subject) {
            [mask("Dreamy background", [MaskCatalog.component(.background)]) { $0.sharpness = -70; $0.exposure = 0.2; $0.contrast = -25; $0.highlights = 20 }]
        },
    ]

    // MARK: - Sky

    static let sky: [MaskPreset] = [
        preset("sky.blueDrama", "Blue drama", .sky, needs: .sky) {
            [mask("Blue drama", [MaskCatalog.component(.sky)]) { $0.exposure = -0.2; $0.temperature = -20; $0.saturation = 20; $0.highlights = -30; $0.dehaze = 25 }]
        },
        preset("sky.deepBlue", "Deep blue", .sky, needs: .sky) {
            [mask("Deep blue", [MaskCatalog.component(.sky)]) { $0.exposure = -0.45; $0.saturation = 30; $0.temperature = -10 }]
        },
        preset("sky.sunset", "Sunset glow", .sky, needs: .sky) {
            [mask("Sunset glow", [MaskCatalog.component(.sky)]) { $0.temperature = 35; $0.tint = 15; $0.saturation = 20; $0.colorAmount = 25; $0.colorHue = 25 }]
        },
        preset("sky.golden", "Golden", .sky, needs: .sky) {
            [mask("Golden sky", [MaskCatalog.component(.sky)]) { $0.temperature = 30; $0.exposure = 0.1; $0.saturation = 10 }]
        },
        preset("sky.moody", "Moody", .sky, needs: .sky) {
            [mask("Moody sky", [MaskCatalog.component(.sky)]) { $0.exposure = -0.5; $0.saturation = -30; $0.clarity = 25; $0.contrast = 20 }]
        },
        preset("sky.pastel", "Pastel", .sky, needs: .sky) {
            [mask("Pastel sky", [MaskCatalog.component(.sky)]) { $0.exposure = 0.3; $0.saturation = -20; $0.contrast = -20; $0.colorAmount = 20; $0.colorHue = 320 }]
        },
    ]

    // MARK: - Travel (whole photo)

    static let travel: [MaskPreset] = [
        MaskPreset(id: "travel.spring", title: "Spring", category: .travel, needs: nil) { document in
            document.color.vibrance += 15
            document.light.exposure += 0.1
            document.mixer.saturation[HueBand.green.rawValue] += 15
            document.mixer.hue[HueBand.yellow.rawValue] -= 10
            document.color.tint -= 4
        },
        MaskPreset(id: "travel.summer", title: "Summer", category: .travel, needs: nil) { document in
            document.color.temperature += 12
            document.color.vibrance += 25
            document.light.contrast += 10
            document.effects.dehaze += 10
        },
        MaskPreset(id: "travel.autumn", title: "Autumn", category: .travel, needs: nil) { document in
            document.color.temperature += 15
            document.mixer.saturation[HueBand.orange.rawValue] += 25
            document.mixer.saturation[HueBand.yellow.rawValue] += 15
            document.mixer.hue[HueBand.green.rawValue] -= 40
        },
        MaskPreset(id: "travel.winter", title: "Winter", category: .travel, needs: nil) { document in
            document.color.temperature -= 15
            document.color.saturation -= 15
            document.light.whites += 15
            document.mixer.saturation[HueBand.blue.rawValue] += 10
        },
        MaskPreset(id: "travel.goldenHour", title: "Golden hour", category: .travel, needs: nil) { document in
            document.color.temperature += 25
            document.color.tint += 8
            document.light.highlights -= 15
            document.color.vibrance += 10
        },
        MaskPreset(id: "travel.tropical", title: "Tropical", category: .travel, needs: nil) { document in
            document.color.vibrance += 30
            document.mixer.hue[HueBand.aqua.rawValue] -= 15
            document.mixer.saturation[HueBand.aqua.rawValue] += 25
            document.mixer.saturation[HueBand.blue.rawValue] += 15
            document.light.exposure += 0.1
        },
    ]

    // MARK: - Body

    static let body: [MaskPreset] = [
        preset("body.tan", "Glowing tan", .body, needs: .people) {
            [mask("Glowing tan", [people([.bodySkin])]) { $0.colorAmount = 25; $0.colorHue = 35; $0.exposure = -0.1; $0.saturation = 10 }]
        },
        preset("body.smooth", "Smooth skin", .body, needs: .people) {
            [mask("Smooth body skin", [people([.bodySkin])]) { $0.texture = -35; $0.clarity = -15 }]
        },
        preset("body.clothesRich", "Richer clothes", .body, needs: .people) {
            [mask("Richer clothes", [people([.clothes])]) { $0.saturation = 30; $0.contrast = 10 }]
        },
        preset("body.clothesBlack", "Deeper blacks", .body, needs: .people) {
            [mask("Deeper blacks", [people([.clothes])]) { $0.blacks = -30; $0.contrast = 15 }]
        },
    ]
}
