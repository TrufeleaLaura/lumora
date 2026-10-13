import Foundation

/// A point that should move from `source` to `target` (in isotropic units, e.g. image-width units).
public struct WarpControl: Equatable, Sendable {
    public var source: SIMD2<Double>
    public var target: SIMD2<Double>

    public init(source: SIMD2<Double>, target: SIMD2<Double>) {
        self.source = source
        self.target = target
    }

    /// A point that stays where it is (anchors keep the background still).
    public static func anchor(_ point: SIMD2<Double>) -> WarpControl {
        WarpControl(source: point, target: point)
    }
}

/// Rigid Moving Least Squares deformation (Schaefer, McPhail & Warren, SIGGRAPH 2006).
/// Produces smooth, locally as-rigid-as-possible warps: features keep their shape while moving.
public enum MovingLeastSquares {
    /// Maps `v` with the deformation defined by `from[i] → to[i]`.
    /// For image warping, pass output positions as `from` and input positions as `to`,
    /// which yields the backward map (where each output pixel samples the input).
    public static func rigid(_ v: SIMD2<Double>, from p: [SIMD2<Double>], to q: [SIMD2<Double>], alpha: Double = 1) -> SIMD2<Double> {
        precondition(p.count == q.count)
        guard !p.isEmpty else { return v }

        var weights = [Double](repeating: 0, count: p.count)
        var weightSum = 0.0
        var pStar = SIMD2<Double>(0, 0)
        var qStar = SIMD2<Double>(0, 0)
        for i in p.indices {
            let d = p[i] - v
            let distanceSquared = d.x * d.x + d.y * d.y
            if distanceSquared < 1e-18 {
                return q[i]
            }
            let w = 1 / pow(distanceSquared, alpha)
            weights[i] = w
            weightSum += w
            pStar += w * p[i]
            qStar += w * q[i]
        }
        pStar /= weightSum
        qStar /= weightSum

        let d = v - pStar
        var fr = SIMD2<Double>(0, 0)
        for i in p.indices {
            let ph = p[i] - pStar
            let qh = q[i] - qStar
            let a = ph.x * d.x + ph.y * d.y
            let b = ph.x * d.y - ph.y * d.x
            fr.x += weights[i] * (qh.x * a - qh.y * b)
            fr.y += weights[i] * (qh.x * b + qh.y * a)
        }
        let frLength = (fr.x * fr.x + fr.y * fr.y).squareRoot()
        let dLength = (d.x * d.x + d.y * d.y).squareRoot()
        guard frLength > 1e-12 else { return v - pStar + qStar }
        return fr / frLength * dLength + qStar
    }
}

/// A smooth local scaling (enlarge/shrink) inside an ellipse, e.g. bigger eyes or fuller lips.
/// Units are isotropic like `WarpControl`.
public struct LocalScale: Equatable, Sendable {
    public var center: SIMD2<Double>
    /// Ellipse radii along the local axes.
    public var radius: SIMD2<Double>
    /// Direction of the local x axis (unit vector).
    public var axis: SIMD2<Double>
    /// Scale factors at the center along local x and y (1 = unchanged).
    public var scale: SIMD2<Double>

    public init(center: SIMD2<Double>, radius: SIMD2<Double>, axis: SIMD2<Double> = SIMD2(1, 0), scale: SIMD2<Double>) {
        self.center = center
        self.radius = radius
        self.axis = axis
        self.scale = scale
    }

    /// Backward offset at `v` (where the output pixel at v samples from, minus v).
    public func backwardOffset(at v: SIMD2<Double>) -> SIMD2<Double> {
        let d = v - center
        let xAxis = axis
        let yAxis = SIMD2(-axis.y, axis.x)
        let a = d.x * xAxis.x + d.y * xAxis.y
        let b = d.x * yAxis.x + d.y * yAxis.y
        let ua: Double = a / max(radius.x, 1e-9)
        let ub: Double = b / max(radius.y, 1e-9)
        let r2: Double = ua * ua + ub * ub
        guard r2 < 1 else { return SIMD2(0, 0) }
        let falloff: Double = (1 - r2) * (1 - r2)
        let sa: Double = 1 + (scale.x - 1) * falloff
        let sb: Double = 1 + (scale.y - 1) * falloff
        let moveA: Double = a / sa - a
        let moveB: Double = b / sb - b
        return xAxis * moveA + yAxis * moveB
    }
}

/// A grid of backward displacements over a rectangular region of the image.
/// Coordinates are normalized to the image (0...1, y up); offsets are normalized too, so the
/// same field warps the preview and the full-resolution export identically.
public struct DisplacementField: Equatable, Sendable {
    /// Region of the image covered by the grid (normalized).
    public var region: CGRectValue
    public var columns: Int
    public var rows: Int
    /// (dx, dy) per vertex, row-major from the bottom row; sample position = output + offset.
    public var offsets: [SIMD2<Float>]

    public init(region: CGRectValue, columns: Int, rows: Int, offsets: [SIMD2<Float>]) {
        self.region = region
        self.columns = columns
        self.rows = rows
        self.offsets = offsets
    }

    public var isEmpty: Bool {
        offsets.allSatisfy { abs($0.x) < 1e-7 && abs($0.y) < 1e-7 }
    }

    /// Builds the field for `controls` given in isotropic units where x spans 0...1 across the
    /// image width and y spans 0...aspect (aspect = height / width).
    /// Displacement fades to zero at the region border so warps never create seams.
    public static func build(
        controls: [WarpControl],
        scales: [LocalScale] = [],
        region: CGRectValue,
        aspect: Double,
        columns: Int = 64,
        rows: Int = 64
    ) -> DisplacementField {
        // Anchor the region border so the background stays put.
        var all = controls
        let borderSteps = 12
        for step in 0..<borderSteps {
            let t = Double(step) / Double(borderSteps)
            for point in [(t, 0.0), (1, t), (1 - t, 1.0), (0, 1 - t)] {
                let x = region.x + point.0 * region.width
                let y = (region.y + point.1 * region.height) * aspect
                all.append(.anchor(SIMD2(x, y)))
            }
        }
        // Backward map: from targets (output) to sources (input).
        let from = all.map(\.target)
        let to = all.map(\.source)
        let hasMoves = controls.contains { $0.source != $0.target }

        var offsets = [SIMD2<Float>](repeating: SIMD2(0, 0), count: columns * rows)
        for row in 0..<rows {
            let fy = Double(row) / Double(rows - 1)
            for column in 0..<columns {
                let fx = Double(column) / Double(columns - 1)
                let x = region.x + fx * region.width
                let y = region.y + fy * region.height
                let v = SIMD2(x, y * aspect)
                var offset = hasMoves ? MovingLeastSquares.rigid(v, from: from, to: to) - v : SIMD2(0, 0)
                for scale in scales {
                    offset += scale.backwardOffset(at: v + offset)
                }
                // Smooth window: 1 inside, falling to 0 at the border.
                let edge = min(min(fx, 1 - fx), min(fy, 1 - fy))
                let window = smoothstep(0, 0.18, edge)
                let dx = offset.x * window
                let dy = offset.y / max(aspect, 1e-9) * window
                offsets[row * columns + column] = SIMD2(Float(dx), Float(dy))
            }
        }
        return DisplacementField(region: region, columns: columns, rows: rows, offsets: offsets)
    }

    private static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Bilinear lookup of the offset at a normalized image position (zero outside the region).
    public func offset(atX x: Double, y: Double) -> SIMD2<Double> {
        let fx = (x - region.x) / region.width
        let fy = (y - region.y) / region.height
        guard fx >= 0, fx <= 1, fy >= 0, fy <= 1, columns > 1, rows > 1 else { return SIMD2(0, 0) }
        let gx = fx * Double(columns - 1)
        let gy = fy * Double(rows - 1)
        let x0 = min(Int(gx), columns - 2), y0 = min(Int(gy), rows - 2)
        let tx = gx - Double(x0), ty = gy - Double(y0)
        func at(_ c: Int, _ r: Int) -> SIMD2<Double> {
            let o = offsets[r * columns + c]
            return SIMD2(Double(o.x), Double(o.y))
        }
        let bottom = at(x0, y0) * (1 - tx) + at(x0 + 1, y0) * tx
        let top = at(x0, y0 + 1) * (1 - tx) + at(x0 + 1, y0 + 1) * tx
        return bottom * (1 - ty) + top * ty
    }
}

/// A Codable, Sendable rectangle (normalized coordinates).
public struct CGRectValue: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    /// Grown around its center by `factor` and clamped to the unit square.
    public func expanded(by factor: Double) -> CGRectValue {
        let w = width * factor, h = height * factor
        let nx = max(0, midX - w / 2), ny = max(0, midY - h / 2)
        return CGRectValue(x: nx, y: ny, width: min(1, midX + w / 2) - nx, height: min(1, midY + h / 2) - ny)
    }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px <= x + width && py >= y && py <= y + height
    }
}
