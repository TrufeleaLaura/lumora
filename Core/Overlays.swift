import Foundation

/// Procedural texture overlays (Tezza-style). Each has a strength (0...100) and a variation.
public struct OverlaySettings: Codable, Equatable, Sendable {
    public var dust: Double = 0
    public var scratches: Double = 0
    public var lightLeak: Double = 0
    public var paper: Double = 0
    public var plastic: Double = 0
    public var shadows: Double = 0
    public var prism: Double = 0
    /// Variation of each overlay (0...5), so the same overlay can look different.
    public var dustStyle: Double = 0
    public var lightLeakStyle: Double = 0
    public var shadowStyle: Double = 0
    public var prismStyle: Double = 0

    public init() {}

    public var isIdentity: Bool {
        dust == 0 && scratches == 0 && lightLeak == 0 && paper == 0 && plastic == 0 && shadows == 0 && prism == 0
    }
}

/// Borders and retro camera frames.
public enum FrameStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case none, border, polaroid, film, super8, vhs

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: return "None"
        case .border: return "Border"
        case .polaroid: return "Instant"
        case .film: return "35 mm"
        case .super8: return "Super 8"
        case .vhs: return "VHS"
        }
    }

    public var symbol: String {
        switch self {
        case .none: return "nosign"
        case .border: return "square"
        case .polaroid: return "rectangle.portrait.bottomhalf.filled"
        case .film: return "film"
        case .super8: return "video"
        case .vhs: return "tv"
        }
    }
}

/// An sRGB color (0...1).
public struct RGBColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let white = RGBColor(1, 1, 1)
    public static let black = RGBColor(0, 0, 0)
    public static let cream = RGBColor(0.96, 0.94, 0.89)
    public static let stamp = RGBColor(1, 0.55, 0.16)

    /// Palette offered for text, stickers and borders.
    public static let palette: [RGBColor] = [
        .white, .black, .cream, RGBColor(0.93, 0.8, 0.74), RGBColor(0.85, 0.62, 0.58), RGBColor(0.78, 0.3, 0.32),
        RGBColor(0.96, 0.76, 0.47), .stamp, RGBColor(0.55, 0.62, 0.45), RGBColor(0.45, 0.58, 0.72), RGBColor(0.36, 0.28, 0.24),
    ]
}

public struct FrameSettings: Codable, Equatable, Sendable {
    public var style: FrameStyle = .none
    /// Border width for `.border`, 0...100 (percent of 10 % of the short side).
    public var width: Double = 40
    public var color: RGBColor = .white
    /// Orange digital date in the corner, like a film point-and-shoot.
    public var dateStamp = false
    /// The stamped text (set from the photo's capture date when turned on).
    public var dateText = ""

    public init() {}

    public var isIdentity: Bool { style == .none && !dateStamp }
}

/// Fonts offered for text (built into iOS).
public enum TextFont: String, Codable, CaseIterable, Sendable, Identifiable {
    case sans, serif, rounded, mono, didot, futura, avenir, baskerville, bodoni, typewriter, script, hand, marker, chalk

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sans: return "Sans"
        case .serif: return "Serif"
        case .rounded: return "Rounded"
        case .mono: return "Mono"
        case .didot: return "Didot"
        case .futura: return "Futura"
        case .avenir: return "Avenir"
        case .baskerville: return "Baskerville"
        case .bodoni: return "Bodoni"
        case .typewriter: return "Typewriter"
        case .script: return "Script"
        case .hand: return "Handwritten"
        case .marker: return "Marker"
        case .chalk: return "Chalk"
        }
    }

    /// PostScript name of an iOS font (nil = a system font design).
    public var fontName: String? {
        switch self {
        case .sans, .serif, .rounded, .mono: return nil
        case .didot: return "Didot"
        case .futura: return "Futura-Medium"
        case .avenir: return "AvenirNext-DemiBold"
        case .baskerville: return "Baskerville"
        case .bodoni: return "BodoniSvtyTwoITCTT-Book"
        case .typewriter: return "AmericanTypewriter"
        case .script: return "SnellRoundhand-Bold"
        case .hand: return "BradleyHandITCTT-Bold"
        case .marker: return "MarkerFelt-Wide"
        case .chalk: return "Chalkduster"
        }
    }
}

public enum TextAlign: String, Codable, CaseIterable, Sendable {
    case left, center, right
}

/// A text or sticker placed on the photo. Positions are normalized (0...1, y up) within the
/// cropped photo (inside any frame); size is the text height as a fraction of the photo width.
public struct TextLayer: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    public var text = "Text"
    /// A sticker draws an SF Symbol (by name) instead of text.
    public var symbol: String?
    public var font: TextFont = .serif
    public var size: Double = 0.07
    public var color: RGBColor = .white
    public var position = SIMD2<Double>(0.5, 0.5)
    /// Degrees, counterclockwise.
    public var rotation: Double = 0
    public var opacity: Double = 100
    /// Extra letter spacing, 0...100.
    public var spacing: Double = 0
    public var alignment: TextAlign = .center
    public var shadow = false
    /// A rounded label behind the text.
    public var background = false
    public var backgroundColor: RGBColor = .white
    /// 0...100
    public var backgroundOpacity: Double = 90
    /// An outline around the letters.
    public var outline = false
    public var outlineColor: RGBColor = .black
    /// A neon-like glow in the text color.
    public var glow = false
    public var uppercase = false
    /// Extra space between lines, 0...100.
    public var lineSpacing: Double = 0

    public init(text: String = "Text", symbol: String? = nil) {
        self.text = text
        self.symbol = symbol
    }

    public var isSticker: Bool { symbol != nil }
}

/// One-tap text styles (current favourites for stories and captions).
public struct TextStylePreset: Identifiable, Sendable {
    public let id: String
    public let title: String
    let apply: @Sendable (inout TextLayer) -> Void

    /// Applies the style to a layer, keeping its text and position.
    public func style(_ layer: inout TextLayer) {
        let text = layer.text, position = layer.position, rotation = layer.rotation, symbol = layer.symbol
        var fresh = TextLayer(text: text, symbol: symbol)
        fresh.id = layer.id
        fresh.position = position
        fresh.rotation = rotation
        apply(&fresh)
        layer = fresh
    }

    public static let all: [TextStylePreset] = [
        TextStylePreset(id: "minimal", title: "Minimal") { $0.font = .sans; $0.size = 0.045; $0.spacing = 35; $0.uppercase = true },
        TextStylePreset(id: "elegant", title: "Elegant") { $0.font = .didot; $0.size = 0.085 },
        TextStylePreset(id: "signature", title: "Signature") { $0.font = .script; $0.size = 0.1; $0.shadow = true },
        TextStylePreset(id: "boldCaps", title: "Bold caps") { $0.font = .futura; $0.size = 0.08; $0.uppercase = true; $0.spacing = 10 },
        TextStylePreset(id: "magazine", title: "Magazine") { $0.font = .bodoni; $0.size = 0.13; $0.uppercase = true },
        TextStylePreset(id: "typewriter", title: "Typewriter") { layer in
            layer.font = .typewriter; layer.size = 0.042; layer.color = .black
            layer.background = true; layer.backgroundColor = .cream
        },
        TextStylePreset(id: "neon", title: "Neon") { layer in
            layer.font = .rounded; layer.size = 0.08; layer.color = RGBColor(1, 0.45, 0.75); layer.glow = true
        },
        TextStylePreset(id: "label", title: "Label") { layer in
            layer.font = .sans; layer.size = 0.04; layer.color = .black; layer.uppercase = true; layer.spacing = 20
            layer.background = true; layer.backgroundColor = .white
        },
        TextStylePreset(id: "handwritten", title: "Handwritten") { $0.font = .hand; $0.size = 0.075; $0.shadow = true },
        TextStylePreset(id: "outline", title: "Outline") { layer in
            layer.font = .futura; layer.size = 0.1; layer.uppercase = true; layer.outline = true; layer.outlineColor = .black
        },
        TextStylePreset(id: "retro", title: "Retro") { $0.font = .marker; $0.size = 0.08; $0.color = .stamp; $0.shadow = true },
        TextStylePreset(id: "caption", title: "Caption") { $0.font = .hand; $0.size = 0.05; $0.color = .black },
        TextStylePreset(id: "pinkLabel", title: "Pink label") { layer in
            layer.font = .rounded; layer.size = 0.045; layer.color = .white
            layer.background = true; layer.backgroundColor = RGBColor(0.93, 0.47, 0.62)
        },
        TextStylePreset(id: "quote", title: "Quote") { layer in
            layer.font = .serif; layer.size = 0.055; layer.lineSpacing = 40; layer.shadow = true
        },
    ]
}

/// Stickers offered in the picker (SF Symbols).
public enum StickerCatalog {
    public static let symbols: [String] = [
        "heart.fill", "heart", "star.fill", "sparkle", "sparkles", "sun.max.fill", "moon.stars.fill", "cloud.fill",
        "leaf.fill", "camera.fill", "film", "music.note", "airplane", "location.fill", "crown.fill", "bolt.fill",
        "flame.fill", "drop.fill", "snowflake", "smiley", "hand.thumbsup.fill", "seal.fill", "rosette", "gift.fill",
    ]
}

/// Where the photo sits inside a frame: output size and the photo's rectangle (pixels, y up).
public enum FrameLayout {
    public static func layout(_ frame: FrameSettings, contentWidth: Double, contentHeight: Double) -> (width: Double, height: Double, content: CGRectValue) {
        let short = min(contentWidth, contentHeight)
        switch frame.style {
        case .none, .vhs:
            return (contentWidth, contentHeight, CGRectValue(x: 0, y: 0, width: contentWidth, height: contentHeight))
        case .border:
            let b = (short * 0.1 * frame.width / 100).rounded()
            return (contentWidth + 2 * b, contentHeight + 2 * b, CGRectValue(x: b, y: b, width: contentWidth, height: contentHeight))
        case .polaroid:
            let side = (short * 0.065).rounded()
            let bottom = (short * 0.26).rounded()
            return (contentWidth + 2 * side, contentHeight + side + bottom, CGRectValue(x: side, y: bottom, width: contentWidth, height: contentHeight))
        case .film:
            // Sprocket strips along the long edges.
            if contentWidth >= contentHeight {
                let strip = (contentHeight * 0.16).rounded()
                let end = (contentWidth * 0.02).rounded()
                return (contentWidth + 2 * end, contentHeight + 2 * strip, CGRectValue(x: end, y: strip, width: contentWidth, height: contentHeight))
            } else {
                let strip = (contentWidth * 0.16).rounded()
                let end = (contentHeight * 0.02).rounded()
                return (contentWidth + 2 * strip, contentHeight + 2 * end, CGRectValue(x: strip, y: end, width: contentWidth, height: contentHeight))
            }
        case .super8:
            let border = (short * 0.09).rounded()
            let left = (short * 0.2).rounded()
            return (contentWidth + left + border, contentHeight + 2 * border, CGRectValue(x: left, y: border, width: contentWidth, height: contentHeight))
        }
    }
}
