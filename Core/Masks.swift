import Foundation

/// Adjustments applied inside a mask (Lightroom's local adjustment set). All 0 = no change.
public struct LocalAdjustments: Codable, Hashable, Sendable {
    /// EV stops, -4...+4.
    public var exposure: Double = 0
    /// -100...+100 for the rest unless noted.
    public var contrast: Double = 0
    public var highlights: Double = 0
    public var shadows: Double = 0
    public var whites: Double = 0
    public var blacks: Double = 0
    public var temperature: Double = 0
    public var tint: Double = 0
    /// Hue shift of all colors.
    public var hue: Double = 0
    public var saturation: Double = 0
    public var texture: Double = 0
    public var clarity: Double = 0
    public var dehaze: Double = 0
    /// Negative values soften.
    public var sharpness: Double = 0
    /// Noise reduction, 0...100.
    public var noise: Double = 0
    /// Color wash: hue 0...360 and amount 0...100.
    public var colorHue: Double = 30
    public var colorAmount: Double = 0

    public init() {}

    public var isIdentity: Bool {
        var normalized = self
        normalized.colorHue = LocalAdjustments().colorHue
        return normalized == LocalAdjustments()
    }
}

/// How a component combines with the components before it.
public enum MaskMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case add, subtract, intersect

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .add: return "Add"
        case .subtract: return "Subtract"
        case .intersect: return "Intersect"
        }
    }

    public var symbol: String {
        switch self {
        case .add: return "plus.circle"
        case .subtract: return "minus.circle"
        case .intersect: return "circle.circle"
        }
    }
}

/// What a mask component selects.
public enum MaskKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// The main subject(s) (Vision foreground instances, falling back to people).
    case subject
    case background
    case sky
    /// Objects picked by tapping (foreground instances under the tapped points).
    case object
    /// People or parts of people (face skin, hair, lips, clothes…).
    case people
    case brush
    case linear
    case radial
    /// Colors similar to sampled colors.
    case color
    /// A brightness range.
    case luminance
    /// Snapseed-style control point: a soft circle that follows similar colors.
    case point

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .subject: return "Subject"
        case .background: return "Background"
        case .sky: return "Sky"
        case .object: return "Object"
        case .people: return "People"
        case .brush: return "Brush"
        case .linear: return "Linear"
        case .radial: return "Radial"
        case .color: return "Color range"
        case .luminance: return "Luminance"
        case .point: return "Control point"
        }
    }

    public var symbol: String {
        switch self {
        case .subject: return "person.crop.rectangle"
        case .background: return "rectangle.dashed"
        case .sky: return "cloud.sun"
        case .object: return "hand.tap"
        case .people: return "person.2"
        case .brush: return "paintbrush.pointed"
        case .linear: return "rectangle.split.1x2"
        case .radial: return "circle.dashed"
        case .color: return "eyedropper"
        case .luminance: return "sun.min"
        case .point: return "smallcircle.filled.circle"
        }
    }

    /// Kinds whose content is found automatically (no drawing needed).
    public var isAutomatic: Bool {
        switch self {
        case .subject, .background, .sky, .people: return true
        default: return false
        }
    }
}

/// Parts of a person that a People mask can select.
public enum PersonPart: String, Codable, CaseIterable, Sendable, Identifiable {
    case person, faceSkin, bodySkin, eyes, iris, brows, lips, teeth, hair, clothes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .person: return "Entire person"
        case .faceSkin: return "Face skin"
        case .bodySkin: return "Body skin"
        case .eyes: return "Eye whites"
        case .iris: return "Iris & pupil"
        case .brows: return "Eyebrows"
        case .lips: return "Lips"
        case .teeth: return "Teeth"
        case .hair: return "Hair"
        case .clothes: return "Clothes"
        }
    }
}

/// One brush stroke in normalized image coordinates (y up). Sizes are fractions of the image width.
public struct BrushStroke: Codable, Hashable, Sendable {
    public var points: [SIMD2<Double>] = []
    /// Radius as a fraction of the image width.
    public var radius: Double = 0.05
    /// 0...100: 0 = hard edge, 100 = soft from the center.
    public var feather: Double = 50
    /// 0...100: opacity of one stroke.
    public var flow: Double = 100
    public var erase = false

    public init(points: [SIMD2<Double>] = [], radius: Double = 0.05, feather: Double = 50, flow: Double = 100, erase: Bool = false) {
        self.points = points
        self.radius = radius
        self.feather = feather
        self.flow = flow
        self.erase = erase
    }
}

/// One building block of a mask. Which fields matter depends on `kind`; positions are
/// normalized image coordinates (0...1, y up) of the unrotated, uncropped photo.
public struct MaskComponent: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    public var kind: MaskKind = .brush
    public var mode: MaskMode = .add
    public var inverted = false

    /// Linear: full-effect line. Radial / point: center.
    public var start = SIMD2<Double>(0.5, 0.7)
    /// Linear: zero-effect line.
    public var end = SIMD2<Double>(0.5, 0.4)
    /// Radial: semi-axes (fractions of the image width). Point: x is the radius.
    public var radius = SIMD2<Double>(0.3, 0.22)
    /// Radial: rotation in degrees.
    public var angle: Double = 0
    /// Radial edge softness 0...100.
    public var feather: Double = 50

    /// Color range / point: sampled colors in OKLab (L, a, b).
    public var colors: [SIMD3<Double>] = []
    /// Luminance range (perceptual 0...1).
    public var range = SIMD2<Double>(0.6, 1)
    /// Color / luminance / point tolerance and smoothness, 0...100.
    public var refine: Double = 50

    public var strokes: [BrushStroke] = []
    /// Brush strokes snap to edges in the photo (Lightroom "Auto Mask").
    public var autoEdge = false

    /// People: parts to include.
    public var parts: [PersonPart] = [.person]
    /// People: a point on the chosen person (face or body), nil = everyone.
    public var person: SIMD2<Double>?

    /// Object: tapped points.
    public var points: [SIMD2<Double>] = []

    public init(kind: MaskKind = .brush, mode: MaskMode = .add) {
        self.kind = kind
        self.mode = mode
    }
}

/// A named mask: components combined in order, plus the adjustments it applies.
public struct Mask: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    public var name = "Mask"
    public var isVisible = true
    /// 0...100, overall strength of the adjustments.
    public var amount: Double = 100
    public var components: [MaskComponent] = []
    public var adjustments = LocalAdjustments()

    public init(name: String = "Mask", components: [MaskComponent] = []) {
        self.name = name
        self.components = components
    }

    /// True when rendering the mask can change the photo.
    public var isActive: Bool {
        isVisible && amount > 0 && !components.isEmpty && !adjustments.isIdentity
    }
}

public enum MaskCatalog {
    /// A new component of `kind` with sensible defaults.
    public static func component(_ kind: MaskKind, mode: MaskMode = .add) -> MaskComponent {
        var component = MaskComponent(kind: kind, mode: mode)
        switch kind {
        case .background:
            // The subject, inverted.
            component.inverted = true
        case .linear:
            component.start = SIMD2(0.5, 0.95)
            component.end = SIMD2(0.5, 0.55)
        case .radial:
            component.start = SIMD2(0.5, 0.5)
        case .point:
            component.start = SIMD2(0.5, 0.5)
            component.radius = SIMD2(0.15, 0.15)
        case .luminance:
            component.range = SIMD2(0.65, 1)
            component.refine = 30
        default:
            break
        }
        return component
    }

    /// Useful starting adjustments for automatic masks (Lightroom-style suggestions).
    public static func suggestedName(for kind: MaskKind, existing: [Mask]) -> String {
        let base = kind.title
        let count = existing.filter { $0.name.hasPrefix(base) }.count
        return count == 0 ? base : "\(base) \(count + 1)"
    }

    public static func sliders(maskIndex: Int) -> [SliderSpec] {
        let path = \EditDocument.masks[maskIndex].adjustments
        func spec(_ id: String, _ title: String, _ key: WritableKeyPath<LocalAdjustments, Double>, range: ClosedRange<Double> = -100...100, style: SliderValueStyle = .signedInteger) -> SliderSpec {
            SliderSpec(id: "mask.\(id)", title: title, range: range, style: style, keyPath: path.appending(path: key))
        }
        return [
            SliderSpec(id: "mask.amount", title: "Amount", range: 0...100, defaultValue: 100, style: .integer, keyPath: \EditDocument.masks[maskIndex].amount),
            spec("exposure", "Exposure", \.exposure, range: -4...4, style: .ev),
            spec("contrast", "Contrast", \.contrast),
            spec("highlights", "Highlights", \.highlights),
            spec("shadows", "Shadows", \.shadows),
            spec("whites", "Whites", \.whites),
            spec("blacks", "Blacks", \.blacks),
            spec("temperature", "Temperature", \.temperature),
            spec("tint", "Tint", \.tint),
            spec("hue", "Hue", \.hue),
            spec("saturation", "Saturation", \.saturation),
            spec("texture", "Texture", \.texture),
            spec("clarity", "Clarity", \.clarity),
            spec("dehaze", "Dehaze", \.dehaze),
            spec("sharpness", "Sharpness", \.sharpness),
            spec("noise", "Noise reduction", \.noise, range: 0...100, style: .integer),
            spec("colorAmount", "Color amount", \.colorAmount, range: 0...100, style: .integer),
            SliderSpec(id: "mask.colorHue", title: "Color hue", range: 0...360, defaultValue: 30, style: .degrees, keyPath: path.appending(path: \.colorHue)),
        ]
    }
}

/// Rasterizes brush strokes into a coverage buffer (pure Swift, so it can be tested anywhere).
public enum BrushRasterizer {
    /// Coverage 0...1, `width × height`, rows top-down. Coordinates are normalized (y up);
    /// a stroke's radius is a fraction of the image width.
    public static func rasterize(_ strokes: [BrushStroke], width: Int, height: Int) -> [Float] {
        var coverage = [Float](repeating: 0, count: width * height)
        guard width > 0, height > 0 else { return coverage }
        var stroke = [Float](repeating: 0, count: width * height)
        let w = Double(width), h = Double(height)

        for item in strokes where !item.points.isEmpty {
            let radius = max(item.radius * w, 0.5)
            let feather = min(max(item.feather / 100, 0), 1)
            let inner = radius * (1 - feather)
            let flow = Float(min(max(item.flow / 100, 0), 1))
            guard flow > 0 else { continue }

            // Dab centers along the path in pixels (y down).
            let pixels = item.points.map { SIMD2($0.x * w, (1 - $0.y) * h) }
            let spacing = max(radius * 0.2, 0.5)
            var dabs: [SIMD2<Double>] = [pixels[0]]
            for index in 1..<max(pixels.count, 1) where index < pixels.count {
                let a = pixels[index - 1], b = pixels[index]
                let delta: SIMD2<Double> = b - a
                let distance = (delta.x * delta.x + delta.y * delta.y).squareRoot()
                let steps = Int((distance / spacing).rounded(.up))
                if steps > 0 {
                    for step in 1...steps {
                        let t = Double(step) / Double(steps)
                        let point: SIMD2<Double> = a + delta * t
                        dabs.append(point)
                    }
                }
            }

            // Stroke coverage = max over dabs, so one stroke has an even opacity.
            var minX = width, minY = height, maxX = -1, maxY = -1
            for dab in dabs {
                let x0 = max(0, Int((dab.x - radius).rounded(.down)))
                let x1 = min(width - 1, Int((dab.x + radius).rounded(.up)))
                let y0 = max(0, Int((dab.y - radius).rounded(.down)))
                let y1 = min(height - 1, Int((dab.y + radius).rounded(.up)))
                guard x0 <= x1, y0 <= y1 else { continue }
                minX = min(minX, x0); maxX = max(maxX, x1)
                minY = min(minY, y0); maxY = max(maxY, y1)
                for y in y0...y1 {
                    let dy = Double(y) + 0.5 - dab.y
                    let row = y * width
                    for x in x0...x1 {
                        let dx = Double(x) + 0.5 - dab.x
                        let distance = (dx * dx + dy * dy).squareRoot()
                        guard distance < radius else { continue }
                        let value: Float
                        if distance <= inner {
                            value = 1
                        } else {
                            let t = (distance - inner) / max(radius - inner, 1e-6)
                            let s = 1 - t
                            value = Float(s * s * (3 - 2 * s))
                        }
                        if value > stroke[row + x] { stroke[row + x] = value }
                    }
                }
            }
            guard maxX >= minX, maxY >= minY else { continue }
            for y in minY...maxY {
                let row = y * width
                for x in minX...maxX {
                    let value = stroke[row + x] * flow
                    stroke[row + x] = 0
                    guard value > 0 else { continue }
                    if item.erase {
                        coverage[row + x] *= 1 - value
                    } else {
                        coverage[row + x] += (1 - coverage[row + x]) * value
                    }
                }
            }
        }
        return coverage
    }
}

/// Pure math for mask shapes (shared by the renderer's tests and the UI handles).
public enum MaskMath {
    /// Linear gradient weight at a normalized point: 1 on the start side, 0 past the end.
    public static func linear(at point: SIMD2<Double>, start: SIMD2<Double>, end: SIMD2<Double>, aspect: Double) -> Double {
        let p = SIMD2(point.x, point.y * aspect)
        let a = SIMD2(start.x, start.y * aspect)
        let b = SIMD2(end.x, end.y * aspect)
        let axis: SIMD2<Double> = b - a
        let lengthSquared = max(axis.x * axis.x + axis.y * axis.y, 1e-12)
        let offset: SIMD2<Double> = p - a
        let t = min(max((offset.x * axis.x + offset.y * axis.y) / lengthSquared, 0), 1)
        let s = 1 - t
        return s * s * (3 - 2 * s)
    }

    /// Radial weight: 1 inside the feathered ellipse, 0 outside.
    public static func radial(at point: SIMD2<Double>, center: SIMD2<Double>, radius: SIMD2<Double>, angle: Double, feather: Double, aspect: Double) -> Double {
        let p = SIMD2(point.x - center.x, (point.y - center.y) * aspect)
        let radians = angle * .pi / 180
        let c = cos(radians), s = sin(radians)
        let local = SIMD2(p.x * c + p.y * s, -p.x * s + p.y * c)
        let rx = max(radius.x, 1e-6), ry = max(radius.y, 1e-6)
        let d = ((local.x / rx) * (local.x / rx) + (local.y / ry) * (local.y / ry)).squareRoot()
        let f = min(max(feather / 100, 0), 1)
        let inner = 1 - f
        if d <= inner { return 1 }
        if d >= 1 { return 0 }
        let t = (d - inner) / max(1 - inner, 1e-6)
        let u = 1 - t
        return u * u * (3 - 2 * u)
    }

    /// Combines component weights in order (add = union, subtract, intersect).
    public static func combine(_ values: [(value: Double, mode: MaskMode)]) -> Double {
        var result = 0.0
        for (index, item) in values.enumerated() {
            if index == 0 && item.mode != .subtract {
                result = item.value
                continue
            }
            switch item.mode {
            case .add: result = max(result, item.value)
            case .subtract: result *= 1 - item.value
            case .intersect: result *= item.value
            }
        }
        return result
    }
}
