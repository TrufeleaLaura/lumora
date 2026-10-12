import Foundation

/// Curve evaluation for the tone curve tool (all values in perceptual 0...1 space).
public enum ToneCurveMath {
    /// Monotone cubic (Fritsch–Carlson) interpolation through the points, so the curve
    /// never overshoots between control points. Points are sorted by x; outside the
    /// first/last point the curve is flat.
    public static func evaluate(_ points: [CurvePoint], at x: Double) -> Double {
        let pts = sanitized(points)
        guard pts.count >= 2 else { return x }
        if x <= pts[0].x { return pts[0].y }
        if x >= pts[pts.count - 1].x { return pts[pts.count - 1].y }

        let tangents = monotoneTangents(pts)
        var i = 0
        while i < pts.count - 2 && x > pts[i + 1].x { i += 1 }
        let p0 = pts[i], p1 = pts[i + 1]
        let h = p1.x - p0.x
        guard h > 1e-9 else { return p0.y }
        let t = (x - p0.x) / h
        let t2 = t * t, t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        return h00 * p0.y + h10 * h * tangents[i] + h01 * p1.y + h11 * h * tangents[i + 1]
    }

    /// Sorted, de-duplicated, clamped copy of the points.
    public static func sanitized(_ points: [CurvePoint]) -> [CurvePoint] {
        let clamped = points.map { CurvePoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }
        let sorted = clamped.sorted { $0.x < $1.x }
        var result: [CurvePoint] = []
        for point in sorted {
            if let last = result.last, abs(last.x - point.x) < 1e-6 {
                result[result.count - 1] = point
            } else {
                result.append(point)
            }
        }
        return result
    }

    private static func monotoneTangents(_ pts: [CurvePoint]) -> [Double] {
        let n = pts.count
        var slopes = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let dx = pts[i + 1].x - pts[i].x
            slopes[i] = dx > 1e-9 ? (pts[i + 1].y - pts[i].y) / dx : 0
        }
        var m = [Double](repeating: 0, count: n)
        m[0] = slopes[0]
        m[n - 1] = slopes[n - 2]
        if n > 2 {
            for i in 1..<(n - 1) {
                m[i] = slopes[i - 1] * slopes[i] <= 0 ? 0 : (slopes[i - 1] + slopes[i]) / 2
            }
        }
        for i in 0..<(n - 1) {
            if abs(slopes[i]) < 1e-12 {
                m[i] = 0
                m[i + 1] = 0
                continue
            }
            let a = m[i] / slopes[i]
            let b = m[i + 1] / slopes[i]
            let s = a * a + b * b
            if s > 9 {
                let tau = 3 / s.squareRoot()
                m[i] = tau * a * slopes[i]
                m[i + 1] = tau * b * slopes[i]
            }
        }
        return m
    }

    /// Lightroom-style parametric curve. Each region (-100...+100) lifts or lowers a
    /// smooth band of tones: shadows ~0–25 %, darks ~25–50 %, lights ~50–75 %, highlights ~75–100 %.
    public static func parametric(_ settings: ToneCurveSettings, at x: Double) -> Double {
        let regions: [(amount: Double, center: Double)] = [
            (settings.shadows, 0.125),
            (settings.darks, 0.375),
            (settings.lights, 0.625),
            (settings.highlights, 0.875),
        ]
        var y = x
        for region in regions where region.amount != 0 {
            // Smooth bump, zero at the ends of the 0...1 range so black and white stay put.
            let width = 0.22
            let d = (x - region.center) / width
            let bump = exp(-d * d) * (x * (1 - x) * 4).squareRoot()
            y += region.amount / 100 * 0.12 * bump
        }
        return min(max(y, 0), 1)
    }

    /// Lookup table of `count` entries per channel: red, green and blue are each
    /// channel curve applied after the parametric and master curves.
    public static func lookupTable(_ settings: ToneCurveSettings, count: Int = 1024) -> [(Double, Double, Double)] {
        (0..<count).map { index in
            let x = Double(index) / Double(count - 1)
            let master = evaluate(settings.master, at: parametric(settings, at: x))
            return (
                evaluate(settings.red, at: master),
                evaluate(settings.green, at: master),
                evaluate(settings.blue, at: master)
            )
        }
    }

    public static func isLinear(_ points: [CurvePoint]) -> Bool {
        let pts = sanitized(points)
        return pts.allSatisfy { abs($0.x - $0.y) < 1e-6 } && (pts.first?.x ?? 0) <= 1e-6 && (pts.last?.x ?? 1) >= 1 - 1e-6
    }

    public static func isIdentity(_ settings: ToneCurveSettings) -> Bool {
        settings.highlights == 0 && settings.lights == 0 && settings.darks == 0 && settings.shadows == 0
            && isLinear(settings.master) && isLinear(settings.red) && isLinear(settings.green) && isLinear(settings.blue)
    }
}

/// Color helpers shared by the engine and UI.
public enum ColorMath {
    /// HSL (h in degrees, s and l in 0...1) to sRGB 0...1.
    public static func hslToRGB(hue: Double, saturation: Double, lightness: Double) -> (Double, Double, Double) {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let c = (1 - abs(2 * lightness - 1)) * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = lightness - c / 2
        let (r, g, b): (Double, Double, Double)
        switch h {
        case 0..<1: (r, g, b) = (c, x, 0)
        case 1..<2: (r, g, b) = (x, c, 0)
        case 2..<3: (r, g, b) = (0, c, x)
        case 3..<4: (r, g, b) = (0, x, c)
        case 4..<5: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }

    public static func srgbToLinear(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    /// Linear sRGB to OKLab (L, a, b).
    public static func linearSRGBToOklab(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    /// Unit direction in the OKLab a/b plane for a hue-wheel angle (0 = red).
    public static func oklabDirection(forWheelHue hue: Double) -> (Double, Double) {
        let rgb = hslToRGB(hue: hue, saturation: 1, lightness: 0.5)
        let lab = linearSRGBToOklab(srgbToLinear(rgb.0), srgbToLinear(rgb.1), srgbToLinear(rgb.2))
        let length = max((lab.1 * lab.1 + lab.2 * lab.2).squareRoot(), 1e-9)
        return (lab.1 / length, lab.2 / length)
    }
}
