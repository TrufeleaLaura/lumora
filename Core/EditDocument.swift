import Foundation

/// Global tone settings (Lightroom's "Light" panel).
public struct LightSettings: Codable, Equatable, Sendable {
    /// Exposure in EV stops, -5...+5.
    public var exposure: Double
    /// -100...+100
    public var contrast: Double
    /// -100...+100
    public var whites: Double
    /// -100...+100
    public var blacks: Double

    public init(exposure: Double = 0, contrast: Double = 0, whites: Double = 0, blacks: Double = 0) {
        self.exposure = exposure
        self.contrast = contrast
        self.whites = whites
        self.blacks = blacks
    }
}

/// Global color settings (Lightroom's "Color" panel).
public struct ColorSettings: Codable, Equatable, Sendable {
    /// -100 (cooler) ... +100 (warmer)
    public var temperature: Double
    /// -100 (green) ... +100 (magenta)
    public var tint: Double
    /// -100...+100
    public var vibrance: Double
    /// -100 (monochrome) ... +100
    public var saturation: Double

    public init(temperature: Double = 0, tint: Double = 0, vibrance: Double = 0, saturation: Double = 0) {
        self.temperature = temperature
        self.tint = tint
        self.vibrance = vibrance
        self.saturation = saturation
    }
}

/// The complete, non-destructive description of an edit. Rendering a source image
/// through `RenderPipeline` with this document produces the edited result.
public struct EditDocument: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var light: LightSettings
    public var color: ColorSettings

    public init(light: LightSettings = LightSettings(), color: ColorSettings = ColorSettings()) {
        self.formatVersion = 1
        self.light = light
        self.color = color
    }

    /// True when the document makes no change to the image.
    public var isIdentity: Bool {
        light == LightSettings() && color == ColorSettings()
    }
}
