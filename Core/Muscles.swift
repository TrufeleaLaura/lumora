import Foundation

public enum AbsStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case sixPack, eightPack, elevenLine

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sixPack: return "Six-pack"
        case .eightPack: return "Eight-pack"
        case .elevenLine: return "11 abs"
        }
    }
}

/// Procedural muscle relief turned into lighting (light from above).
/// A pattern lives on a unit canvas: u across (0 = person's right side as seen in the photo's
/// left... i.e. the photo's left), v along the body (0 = bottom, 1 = top).
public enum MuscleRelief {
    public enum Pattern: Sendable {
        case abs(AbsStyle)
        case pecs
        case arm
        case vLine
    }

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Rounded dome over a rounded-rectangle footprint: 1 at the center, 0 at the edge.
    static func dome(_ u: Double, _ v: Double, center: SIMD2<Double>, half: SIMD2<Double>) -> Double {
        let du: Double = abs(u - center.x) / max(half.x, 1e-6)
        let dv: Double = abs(v - center.y) / max(half.y, 1e-6)
        let d: Double = pow(pow(du, 3) + pow(dv, 3), 1.0 / 3.0)
        guard d < 1 else { return 0 }
        let inside: Double = 1 - d * d
        return inside * inside
    }

    static func gauss(_ x: Double, _ width: Double) -> Double {
        let t = x / width
        return exp(-t * t)
    }

    /// Soft fade toward the canvas border, so nothing ends in a visible edge.
    static func envelope(_ u: Double, _ v: Double, margin: Double = 0.1) -> Double {
        let across: Double = smoothstep(0, margin, u) * smoothstep(0, margin, 1 - u)
        let along: Double = smoothstep(0, margin, v) * smoothstep(0, margin, 1 - v)
        return across * along
    }

    /// Relief at (u, v): height of the muscle bellies (0...1, lit from above) and the depth of
    /// the grooves between them (0...1, shaded).
    public static func relief(_ pattern: Pattern, u: Double, v: Double) -> (height: Double, groove: Double) {
        let fadeV: Double = smoothstep(0.0, 0.12, v) * (1 - smoothstep(0.88, 1.0, v))
        switch pattern {
        case .abs(let style):
            switch style {
            case .sixPack, .eightPack:
                let rows = style == .sixPack ? 3 : 4
                let top = 0.96, bottom = 0.04
                let rowHeight: Double = (top - bottom) / Double(rows)
                let side: Double = (u - 0.5) * 2
                var height = 0.0
                var groove = 0.0
                for row in 0..<rows {
                    // Row 0 is the lowest; lower bellies are a little narrower.
                    let inset: Double = 0.035 * Double(rows - 1 - row) / Double(max(rows - 1, 1))
                    let centerV: Double = bottom + (Double(row) + 0.5) * rowHeight
                    let half = SIMD2<Double>(0.2 - inset, rowHeight * 0.5)
                    height = max(height, dome(u, v, center: SIMD2(0.29 + inset * 0.5, centerV), half: half))
                    height = max(height, dome(u, v, center: SIMD2(0.71 - inset * 0.5, centerV), half: half))
                    if row > 0 {
                        // Tendinous lines between rows curve up a little toward the sides.
                        let lineV: Double = bottom + Double(row) * rowHeight + 0.03 * side * side
                        let lateral: Double = smoothstep(0.06, 0.16, u) * (1 - smoothstep(0.84, 0.94, u))
                        groove += gauss(v - lineV, 0.022) * lateral * 0.8
                    }
                }
                // Linea alba down the middle and the curved outer edges.
                groove += gauss(u - 0.5, 0.022) * fadeV
                let edgeOffset: Double = 0.07 + 0.03 * (1 - v)
                groove += 0.45 * (gauss(u - edgeOffset, 0.03) + gauss(u - (1 - edgeOffset), 0.03)) * fadeV
                let e = envelope(u, v)
                return (height * e, min(1, groove) * e)
            case .elevenLine:
                let grooves: Double = gauss(u - 0.33, 0.035) + gauss(u - 0.67, 0.035) + 0.35 * gauss(u - 0.5, 0.025)
                let fade: Double = smoothstep(0.0, 0.2, v) * (1 - smoothstep(0.85, 1.0, v))
                return (0, min(1, grooves) * fade * envelope(u, v, margin: 0.05))
            }
        case .pecs:
            let left = dome(u, v, center: SIMD2(0.28, 0.56), half: SIMD2(0.23, 0.36))
            let right = dome(u, v, center: SIMD2(0.72, 0.56), half: SIMD2(0.23, 0.36))
            // Lower pec line: low near the sternum, rising toward the armpits.
            let outer: Double = abs(u - 0.5) / 0.45
            let creaseV: Double = 0.2 + 0.32 * outer * outer
            let lateral: Double = smoothstep(0.02, 0.12, u) * (1 - smoothstep(0.88, 0.98, u))
            var groove: Double = gauss(v - creaseV, 0.05) * lateral
            groove += 0.6 * gauss(u - 0.5, 0.03) * smoothstep(0.15, 0.3, v) * (1 - smoothstep(0.85, 0.98, v))
            let e = envelope(u, v)
            return (max(left, right) * e, min(1, groove) * e)
        case .arm:
            let du: Double = (u - 0.5) / 0.3
            let dv: Double = (v - 0.55) / 0.33
            return (exp(-(du * du) - (dv * dv)) * envelope(u, v), 0)
        case .vLine:
            // Two grooves running from the hip bones down toward the center.
            func groove(_ u0: Double, _ v0: Double, _ u1: Double, _ v1: Double) -> Double {
                let dx = u1 - u0, dy = v1 - v0
                let t = min(max(((u - u0) * dx + (v - v0) * dy) / (dx * dx + dy * dy), 0), 1)
                let px = u0 + t * dx - u
                let py = v0 + t * dy - v
                let distance: Double = (px * px + py * py).squareRoot() / 0.04
                return exp(-distance * distance) * smoothstep(0, 0.25, t) * (1 - smoothstep(0.85, 1, t))
            }
            return (0, min(1, groove(0.08, 0.95, 0.42, 0.08) + groove(0.92, 0.95, 0.58, 0.08)) * envelope(u, v, margin: 0.05))
        }
    }

    /// Lighting for a pattern on a `width` × `height` grid, row-major from the bottom row.
    /// Each entry is (highlight, shadow) in 0...1: the upper halves of the muscle bellies catch
    /// light from above, their lower halves and the grooves between them fall into shadow.
    public static func shading(_ pattern: Pattern, width: Int, height: Int) -> [SIMD2<Float>] {
        var result = [SIMD2<Float>](repeating: SIMD2(0, 0), count: width * height)
        let step = 1.0 / Double(height)
        for row in 0..<height {
            let v = (Double(row) + 0.5) / Double(height)
            for column in 0..<width {
                let u = (Double(column) + 0.5) / Double(width)
                let center = relief(pattern, u: u, v: v)
                let above = relief(pattern, u: u, v: v + step).height
                let below = relief(pattern, u: u, v: v - step).height
                // Height change per unit of v: negative = surface facing up.
                let slope: Double = (above - below) / (2 * step)
                let light: Double = max(0, -slope) * 0.045
                let shade: Double = max(0, slope) * 0.045
                let highlight = min(1, light)
                let shadow = min(1, shade * 0.8 + center.groove * 0.85)
                result[row * width + column] = SIMD2(Float(highlight), Float(shadow))
            }
        }
        return result
    }
}
