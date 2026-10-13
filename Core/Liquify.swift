import Foundation

/// Manual reshaping brushes (Facetune "Reshape" / Photoshop Liquify).
public enum LiquifyTool: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Drags content along with the finger.
    case push
    /// Enlarges under the brush.
    case bloat
    /// Shrinks under the brush.
    case pinch
    /// Brings content back to where it was.
    case restore

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .push: return "Push"
        case .bloat: return "Enlarge"
        case .pinch: return "Shrink"
        case .restore: return "Restore"
        }
    }

    public var symbol: String {
        switch self {
        case .push: return "hand.point.up.left"
        case .bloat: return "plus.magnifyingglass"
        case .pinch: return "minus.magnifyingglass"
        case .restore: return "arrow.uturn.backward.circle"
        }
    }
}

/// One brush stroke. Points are normalized (0...1, y up); radius is a fraction of the width.
public struct LiquifyStroke: Codable, Hashable, Sendable {
    public var tool: LiquifyTool = .push
    public var points: [SIMD2<Double>] = []
    public var radius: Double = 0.08
    /// 0...100
    public var strength: Double = 60

    public init(tool: LiquifyTool = .push, points: [SIMD2<Double>] = [], radius: Double = 0.08, strength: Double = 60) {
        self.tool = tool
        self.points = points
        self.radius = radius
        self.strength = strength
    }
}

public enum LiquifyMath {
    /// The combined backward warp of all strokes over the whole image, or nil if nothing moves.
    public static func field(_ strokes: [LiquifyStroke], aspect: Double, columns: Int = 160) -> DisplacementField? {
        guard strokes.contains(where: { !$0.points.isEmpty }), aspect > 0 else { return nil }
        let cols = max(columns, 8)
        let rows = max(8, Int((Double(cols) * aspect).rounded()))
        let stepX = 1.0 / Double(cols - 1)
        let stepY = aspect / Double(rows - 1)

        // Backward map in isotropic units: where each output grid point samples the input.
        var map = [SIMD2<Double>](repeating: .zero, count: cols * rows)
        for row in 0..<rows {
            for column in 0..<cols {
                map[row * cols + column] = SIMD2(Double(column) * stepX, Double(row) * stepY)
            }
        }
        func sample(_ q: SIMD2<Double>) -> SIMD2<Double> {
            let gx = min(max(q.x / stepX, 0), Double(cols - 1))
            let gy = min(max(q.y / stepY, 0), Double(rows - 1))
            let x0 = min(Int(gx), cols - 2), y0 = min(Int(gy), rows - 2)
            let tx = gx - Double(x0), ty = gy - Double(y0)
            let a = map[y0 * cols + x0], b = map[y0 * cols + x0 + 1]
            let c = map[(y0 + 1) * cols + x0], d = map[(y0 + 1) * cols + x0 + 1]
            let bottom: SIMD2<Double> = a + (b - a) * tx
            let top: SIMD2<Double> = c + (d - c) * tx
            return bottom + (top - bottom) * ty
        }

        for stroke in strokes where !stroke.points.isEmpty {
            let radius = max(stroke.radius, 0.005)
            let strength = min(max(stroke.strength / 100, 0), 1)
            let points = stroke.points.map { SIMD2($0.x, $0.y * aspect) }
            // Dabs every quarter radius along the path; a tap gives a few dabs in one place.
            var dabs: [(center: SIMD2<Double>, delta: SIMD2<Double>)] = []
            if points.count == 1 {
                for _ in 0..<5 { dabs.append((points[0], .zero)) }
            } else {
                for index in 1..<points.count {
                    let from = points[index - 1], to = points[index]
                    let segment: SIMD2<Double> = to - from
                    let length = (segment.x * segment.x + segment.y * segment.y).squareRoot()
                    let steps = max(1, Int((length / (radius * 0.25)).rounded(.up)))
                    let delta: SIMD2<Double> = segment / Double(steps)
                    for step in 1...steps {
                        let center: SIMD2<Double> = from + delta * Double(step)
                        dabs.append((center, delta))
                    }
                }
            }

            for dab in dabs {
                let x0 = max(0, Int(((dab.center.x - radius) / stepX).rounded(.down)))
                let x1 = min(cols - 1, Int(((dab.center.x + radius) / stepX).rounded(.up)))
                let y0 = max(0, Int(((dab.center.y - radius) / stepY).rounded(.down)))
                let y1 = min(rows - 1, Int(((dab.center.y + radius) / stepY).rounded(.up)))
                guard x0 <= x1, y0 <= y1 else { continue }
                var updates: [(Int, SIMD2<Double>)] = []
                for row in y0...y1 {
                    for column in x0...x1 {
                        let p = SIMD2(Double(column) * stepX, Double(row) * stepY)
                        let offset: SIMD2<Double> = p - dab.center
                        let r = (offset.x * offset.x + offset.y * offset.y).squareRoot() / radius
                        guard r < 1 else { continue }
                        let falloff = (1 - r * r) * (1 - r * r)
                        let index = row * cols + column
                        switch stroke.tool {
                        case .push:
                            let move: SIMD2<Double> = dab.delta * (falloff * strength)
                            updates.append((index, sample(p - move)))
                        case .bloat:
                            let move: SIMD2<Double> = offset * (falloff * strength * 0.08)
                            updates.append((index, sample(p - move)))
                        case .pinch:
                            let move: SIMD2<Double> = offset * (falloff * strength * 0.08)
                            updates.append((index, sample(p + move)))
                        case .restore:
                            let current = map[index]
                            let back: SIMD2<Double> = (p - current) * (falloff * strength * 0.35)
                            updates.append((index, current + back))
                        }
                    }
                }
                for (index, value) in updates {
                    map[index] = value
                }
            }
        }

        var offsets = [SIMD2<Float>](repeating: .zero, count: cols * rows)
        var moved = false
        for row in 0..<rows {
            for column in 0..<cols {
                let index = row * cols + column
                let p = SIMD2(Double(column) * stepX, Double(row) * stepY)
                let d: SIMD2<Double> = map[index] - p
                if abs(d.x) > 1e-7 || abs(d.y) > 1e-7 { moved = true }
                offsets[index] = SIMD2(Float(d.x), Float(d.y / aspect))
            }
        }
        guard moved else { return nil }
        return DisplacementField(region: CGRectValue(x: 0, y: 0, width: 1, height: 1), columns: cols, rows: rows, offsets: offsets)
    }
}
