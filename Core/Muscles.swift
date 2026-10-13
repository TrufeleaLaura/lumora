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

    /// Soft rounded block: 1 inside [u0, u1] × [v0, v1], fading over `edge`.
    static func block(_ u: Double, _ v: Double, _ u0: Double, _ u1: Double, _ v0: Double, _ v1: Double, edge: Double) -> Double {
        let across: Double = smoothstep(u0, u0 + edge, u) * (1 - smoothstep(u1 - edge, u1, u))
        let along: Double = smoothstep(v0, v0 + edge, v) * (1 - smoothstep(v1 - edge, v1, v))
        return across * along
    }

    /// Height of the relief at (u, v), 0...1.
    public static func height(_ pattern: Pattern, u: Double, v: Double) -> Double {
        switch pattern {
        case .abs(let style):
            switch style {
            case .sixPack, .eightPack:
                let rows = style == .sixPack ? 3 : 4
                let gap = 0.05
                let rowHeight = (1.0 - gap * Double(rows + 1)) / Double(rows)
                var value = 0.0
                for row in 0..<rows {
                    let v0 = gap + Double(row) * (rowHeight + gap)
                    // Lower blocks are a little narrower, like real abdominals.
                    let inset = 0.04 * Double(rows - 1 - row) / Double(rows)
                    value = max(value, block(u, v, 0.06 + inset, 0.47, v0, v0 + rowHeight, edge: 0.07))
                    value = max(value, block(u, v, 0.53, 0.94 - inset, v0, v0 + rowHeight, edge: 0.07))
                }
                return value
            case .elevenLine:
                let fade: Double = smoothstep(0.0, 0.2, v) * (1 - smoothstep(0.85, 1.0, v))
                let left: Double = (u - 0.33) / 0.035
                let right: Double = (u - 0.67) / 0.035
                let center: Double = (u - 0.5) / 0.025
                let grooves: Double = exp(-left * left) + exp(-right * right) + 0.35 * exp(-center * center)
                return 1 - min(1, grooves) * fade
            }
        case .pecs:
            let left: Double = block(u, v, 0.05, 0.48, 0.12, 0.92, edge: 0.14)
            let right: Double = block(u, v, 0.52, 0.95, 0.12, 0.92, edge: 0.14)
            return max(left, right)
        case .arm:
            let du: Double = (u - 0.5) / 0.3
            let dv: Double = (v - 0.55) / 0.33
            return exp(-(du * du) - (dv * dv))
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
            return 1 - min(1, groove(0.08, 0.95, 0.42, 0.08) + groove(0.92, 0.95, 0.58, 0.08))
        }
    }

    /// Lighting for a pattern on a `width` × `height` grid, row-major from the bottom row.
    /// Each entry is (highlight, shadow) in 0...1: upper edges catch light, lower edges and
    /// grooves fall into shadow.
    public static func shading(_ pattern: Pattern, width: Int, height: Int) -> [SIMD2<Float>] {
        var heights = [Double](repeating: 0, count: width * height)
        for row in 0..<height {
            let v = (Double(row) + 0.5) / Double(height)
            for column in 0..<width {
                let u = (Double(column) + 0.5) / Double(width)
                heights[row * width + column] = MuscleRelief.height(pattern, u: u, v: v)
            }
        }
        var result = [SIMD2<Float>](repeating: SIMD2(0, 0), count: width * height)
        let scale = Double(height) * 0.06
        for row in 0..<height {
            for column in 0..<width {
                let up = heights[min(row + 1, height - 1) * width + column]
                let down = heights[max(row - 1, 0) * width + column]
                let slope = (up - down) * 0.5 * scale
                let h = heights[row * width + column]
                // Facing up (height falls toward the top) catches light; facing down is shaded.
                let light: Double = max(0, -slope)
                let shade: Double = max(0, slope)
                let crevice: Double = (1 - h) * 0.35
                let highlight = min(1, light * 0.9)
                let shadow = min(1, shade + crevice)
                result[row * width + column] = SIMD2(Float(highlight), Float(shadow))
            }
        }
        return result
    }
}
