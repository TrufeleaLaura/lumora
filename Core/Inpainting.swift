import Foundation

/// Content-aware fill: multi-scale PatchMatch with patch voting (Barnes et al. 2009,
/// Wexler et al. 2007). Each hole pixel is rebuilt from similar patches found elsewhere in
/// the image, coarse to fine, so structure (horizons, textures) continues through the hole.
public enum Inpainting {
    /// Fills the pixels where `hole > 0.5`. Pixels are RGB, row-major (top-down).
    /// Known pixels are returned unchanged.
    public static func fill(_ pixels: [SIMD3<Float>], width: Int, height: Int, hole: [Float], patchRadius: Int = 3, seed: UInt64 = 0x9E37_79B9_7F4A_7C15) -> [SIMD3<Float>] {
        guard width > 0, height > 0, pixels.count == width * height, hole.count == width * height else { return pixels }
        let holeMask = hole.map { $0 > 0.5 }
        guard holeMask.contains(true) else { return pixels }

        // Pyramid: halve until the hole is only a few patches across.
        var levels = [Level(width: width, height: height, pixels: pixels, hole: holeMask)]
        while levels.count < 7 {
            let last = levels[levels.count - 1]
            let extent = last.holeExtent()
            let patch = 2 * patchRadius + 1
            if max(extent.width, extent.height) <= patch + 2 || min(last.width, last.height) < patch * 4 { break }
            levels.append(last.downsampled())
        }

        var random = Random(seed: seed)
        var current = levels[levels.count - 1]
        current.diffuseIntoHole()
        var nnf: [Int]? = nil

        for index in stride(from: levels.count - 1, through: 0, by: -1) {
            if index < levels.count - 1 {
                // Start this level from the coarser result.
                let coarse = current
                current = levels[index]
                current.initializeHole(from: coarse)
                nnf = nnf.map { upsample($0, from: coarse, to: current) }
            }
            let iterations = index == 0 ? 3 : (index == levels.count - 1 ? 8 : 5)
            nnf = solve(&current, nnf: nnf, patchRadius: patchRadius, iterations: iterations, random: &random)
        }

        var result = pixels
        for i in 0..<(width * height) where holeMask[i] {
            result[i] = current.pixels[i]
        }
        return result
    }

    // MARK: - Level

    struct Level {
        var width: Int
        var height: Int
        var pixels: [SIMD3<Float>]
        var hole: [Bool]

        func holeExtent() -> (width: Int, height: Int) {
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                for x in 0..<width where hole[y * width + x] {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            return maxX < minX ? (0, 0) : (maxX - minX + 1, maxY - minY + 1)
        }

        /// Half size: known pixels average their known children; any hole child makes a hole.
        func downsampled() -> Level {
            let w = (width + 1) / 2, h = (height + 1) / 2
            var out = [SIMD3<Float>](repeating: .zero, count: w * h)
            var outHole = [Bool](repeating: false, count: w * h)
            for y in 0..<h {
                for x in 0..<w {
                    var sum = SIMD3<Float>.zero
                    var count: Float = 0
                    var anyHole = false
                    for dy in 0..<2 {
                        for dx in 0..<2 {
                            let sx = min(2 * x + dx, width - 1), sy = min(2 * y + dy, height - 1)
                            let i = sy * width + sx
                            if hole[i] {
                                anyHole = true
                            } else {
                                sum += pixels[i]
                                count += 1
                            }
                        }
                    }
                    out[y * w + x] = count > 0 ? sum / count : .zero
                    outHole[y * w + x] = anyHole
                }
            }
            return Level(width: w, height: h, pixels: out, hole: outHole)
        }

        /// Onion-peel diffusion: hole pixels take the average of known neighbors, ring by ring.
        mutating func diffuseIntoHole() {
            var known = hole.map { !$0 }
            var remaining = hole.filter { $0 }.count
            while remaining > 0 {
                var updates: [(Int, SIMD3<Float>)] = []
                for y in 0..<height {
                    for x in 0..<width {
                        let i = y * width + x
                        guard !known[i] else { continue }
                        var sum = SIMD3<Float>.zero
                        var count: Float = 0
                        for dy in -1...1 {
                            for dx in -1...1 where dx != 0 || dy != 0 {
                                let nx = x + dx, ny = y + dy
                                guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                                let j = ny * width + nx
                                if known[j] {
                                    sum += pixels[j]
                                    count += 1
                                }
                            }
                        }
                        if count > 0 { updates.append((i, sum / count)) }
                    }
                }
                if updates.isEmpty { break }
                for (i, value) in updates {
                    pixels[i] = value
                    known[i] = true
                }
                remaining -= updates.count
            }
        }

        /// Hole pixels start from the coarser level's result (bilinear).
        mutating func initializeHole(from coarse: Level) {
            for y in 0..<height {
                for x in 0..<width where hole[y * width + x] {
                    let cx = min(max((Float(x) + 0.5) / 2 - 0.5, 0), Float(coarse.width - 1))
                    let cy = min(max((Float(y) + 0.5) / 2 - 0.5, 0), Float(coarse.height - 1))
                    let x0 = Int(cx), y0 = Int(cy)
                    let x1 = min(x0 + 1, coarse.width - 1), y1 = min(y0 + 1, coarse.height - 1)
                    let tx = cx - Float(x0), ty = cy - Float(y0)
                    let top: SIMD3<Float> = coarse.pixels[y0 * coarse.width + x0] * (1 - tx) + coarse.pixels[y0 * coarse.width + x1] * tx
                    let bottom: SIMD3<Float> = coarse.pixels[y1 * coarse.width + x0] * (1 - tx) + coarse.pixels[y1 * coarse.width + x1] * tx
                    pixels[y * width + x] = top * (1 - ty) + bottom * ty
                }
            }
        }
    }

    // MARK: - PatchMatch

    struct Random {
        var state: UInt64

        init(seed: UInt64) { state = seed == 0 ? 1 : seed }

        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }

        mutating func int(_ bound: Int) -> Int {
            bound <= 0 ? 0 : Int(next() % UInt64(bound))
        }
    }

    /// Valid source centers: the whole patch is inside the image and has no hole pixels.
    static func validSources(_ level: Level, radius r: Int) -> [Bool] {
        let w = level.width, h = level.height
        // Integral image of hole counts.
        var integral = [Int](repeating: 0, count: (w + 1) * (h + 1))
        for y in 0..<h {
            var row = 0
            for x in 0..<w {
                row += level.hole[y * w + x] ? 1 : 0
                integral[(y + 1) * (w + 1) + x + 1] = integral[y * (w + 1) + x + 1] + row
            }
        }
        var valid = [Bool](repeating: false, count: w * h)
        guard w > 2 * r, h > 2 * r else { return valid }
        for y in r..<(h - r) {
            for x in r..<(w - r) {
                let x0 = x - r, y0 = y - r, x1 = x + r + 1, y1 = y + r + 1
                let count = integral[y1 * (w + 1) + x1] - integral[y0 * (w + 1) + x1] - integral[y1 * (w + 1) + x0] + integral[y0 * (w + 1) + x0]
                valid[y * w + x] = count == 0
            }
        }
        return valid
    }

    /// Patch distance (sum of squared differences over the in-bounds part of the target patch),
    /// stopping early once it exceeds `limit`.
    static func distance(_ level: Level, target: Int, source: Int, radius r: Int, limit: Float) -> Float {
        let w = level.width, h = level.height
        let tx = target % w, ty = target / w
        let sx = source % w, sy = source / w
        var total: Float = 0
        for dy in -r...r {
            let ty2 = ty + dy
            guard ty2 >= 0, ty2 < h else { continue }
            let tRow = ty2 * w
            let sRow = (sy + dy) * w
            for dx in -r...r {
                let tx2 = tx + dx
                guard tx2 >= 0, tx2 < w else { continue }
                let d: SIMD3<Float> = level.pixels[tRow + tx2] - level.pixels[sRow + sx + dx]
                total += d.x * d.x + d.y * d.y + d.z * d.z
            }
            if total > limit { return total }
        }
        return total
    }

    /// Runs EM iterations (PatchMatch search + voting) on one level; returns the nearest-neighbor
    /// field (source index per pixel, -1 where unused).
    static func solve(_ level: inout Level, nnf initial: [Int]?, patchRadius r: Int, iterations: Int, random: inout Random) -> [Int] {
        let w = level.width, h = level.height
        let count = w * h
        let valid = validSources(level, radius: r)
        let sources = (0..<count).filter { valid[$0] }
        guard !sources.isEmpty else {
            level.diffuseIntoHole()
            return [Int](repeating: -1, count: count)
        }

        // Targets: pixels whose patch touches the hole.
        var isTarget = [Bool](repeating: false, count: count)
        for y in 0..<h {
            for x in 0..<w where level.hole[y * w + x] {
                for dy in -r...r {
                    for dx in -r...r {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                        isTarget[ny * w + nx] = true
                    }
                }
            }
        }
        let targets = (0..<count).filter { isTarget[$0] }

        var nnf = initial ?? [Int](repeating: -1, count: count)
        var cost = [Float](repeating: .infinity, count: count)
        for t in targets {
            if nnf[t] < 0 || !valid[nnf[t]] {
                nnf[t] = sources[random.int(sources.count)]
            }
            cost[t] = distance(level, target: t, source: nnf[t], radius: r, limit: .infinity)
        }

        func tryCandidate(_ t: Int, _ candidate: Int) {
            guard candidate >= 0, candidate < count, valid[candidate], candidate != nnf[t] else { return }
            let d = distance(level, target: t, source: candidate, radius: r, limit: cost[t])
            if d < cost[t] {
                cost[t] = d
                nnf[t] = candidate
            }
        }

        let maxRadius = max(w, h)
        for iteration in 0..<iterations {
            // Recompute costs: the hole's pixels changed in the last vote.
            if iteration > 0 {
                for t in targets {
                    cost[t] = distance(level, target: t, source: nnf[t], radius: r, limit: .infinity)
                }
            }
            for pass in 0..<2 {
                let forward = (iteration + pass) % 2 == 0
                let order: [Int] = forward ? targets : targets.reversed()
                let step = forward ? 1 : -1
                for t in order {
                    let x = t % w, y = t / w
                    // Propagation: a neighbor's match, shifted back by one pixel.
                    let nx = x - step, ny = y - step
                    if nx >= 0, nx < w, isTarget[y * w + nx], nnf[y * w + nx] >= 0 {
                        let s = nnf[y * w + nx]
                        let sx = s % w + step
                        if sx >= 0, sx < w { tryCandidate(t, (s / w) * w + sx) }
                    }
                    if ny >= 0, ny < h, isTarget[ny * w + x], nnf[ny * w + x] >= 0 {
                        let s = nnf[ny * w + x]
                        let sy = s / w + step
                        if sy >= 0, sy < h { tryCandidate(t, sy * w + s % w) }
                    }
                    // Random search around the current match, halving the window.
                    var radius = maxRadius
                    let best = nnf[t]
                    let bx = best % w, by = best / w
                    while radius >= 1 {
                        let cx = bx + random.int(2 * radius + 1) - radius
                        let cy = by + random.int(2 * radius + 1) - radius
                        if cx >= 0, cy >= 0, cx < w, cy < h { tryCandidate(t, cy * w + cx) }
                        radius /= 2
                    }
                }
            }

            // Voting: each hole pixel becomes a weighted average of the overlapping patches' pixels.
            var meanCost: Float = 0
            for t in targets { meanCost += cost[t] }
            meanCost = max(meanCost / Float(targets.count), 1e-6)
            var sum = [SIMD3<Float>](repeating: .zero, count: count)
            var weight = [Float](repeating: 0, count: count)
            for t in targets {
                let s = nnf[t]
                let weightT = exp(-cost[t] / (2 * meanCost))
                let tx = t % w, ty = t / w
                let sx = s % w, sy = s / w
                for dy in -r...r {
                    let qy = ty + dy
                    guard qy >= 0, qy < h else { continue }
                    for dx in -r...r {
                        let qx = tx + dx
                        guard qx >= 0, qx < w else { continue }
                        let q = qy * w + qx
                        guard level.hole[q] else { continue }
                        sum[q] += level.pixels[(sy + dy) * w + sx + dx] * weightT
                        weight[q] += weightT
                    }
                }
            }
            for q in 0..<count where level.hole[q] && weight[q] > 0 {
                level.pixels[q] = sum[q] / weight[q]
            }
        }
        return nnf
    }

    /// Doubles a nearest-neighbor field to the next finer level.
    static func upsample(_ nnf: [Int], from coarse: Level, to fine: Level) -> [Int] {
        var result = [Int](repeating: -1, count: fine.width * fine.height)
        for y in 0..<fine.height {
            for x in 0..<fine.width {
                let cx = min(x / 2, coarse.width - 1), cy = min(y / 2, coarse.height - 1)
                let s = nnf[cy * coarse.width + cx]
                guard s >= 0 else { continue }
                let sx = min(2 * (s % coarse.width) + (x % 2), fine.width - 1)
                let sy = min(2 * (s / coarse.width) + (y % 2), fine.height - 1)
                result[y * fine.width + x] = sy * fine.width + sx
            }
        }
        return result
    }
}
