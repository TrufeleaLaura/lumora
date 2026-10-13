import Foundation

/// Spot and object retouching tools.
public enum RetouchTool: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Content-aware fill of small spots (blemishes, dust).
    case heal
    /// Copies pixels from another area.
    case clone
    /// Content-aware fill of larger areas or tapped objects.
    case remove

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .heal: return "Heal"
        case .clone: return "Clone"
        case .remove: return "Remove"
        }
    }

    public var symbol: String {
        switch self {
        case .heal: return "bandage"
        case .clone: return "square.on.square.dashed"
        case .remove: return "eraser"
        }
    }
}

/// One retouch step. Areas are brush strokes in normalized image coordinates (y up).
public struct RetouchOperation: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    public var tool: RetouchTool = .heal
    public var strokes: [BrushStroke] = []
    /// Remove: objects picked by tapping (filled with their Vision instance masks).
    public var objectPoints: [SIMD2<Double>] = []
    /// Clone: offset from the painted area to its source (normalized x and y).
    public var sourceOffset = SIMD2<Double>(0.1, 0)
    /// 0...100
    public var opacity: Double = 100

    public init(tool: RetouchTool = .heal, strokes: [BrushStroke] = []) {
        self.tool = tool
        self.strokes = strokes
    }

    /// Normalized bounds of the painted area (including brush radius), or nil if empty.
    public func bounds(aspect: Double) -> CGRectValue? {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for stroke in strokes {
            let rx = stroke.radius
            let ry = stroke.radius / max(aspect, 1e-9)
            for p in stroke.points {
                minX = Swift.min(minX, p.x - rx)
                maxX = Swift.max(maxX, p.x + rx)
                minY = Swift.min(minY, p.y - ry)
                maxY = Swift.max(maxY, p.y + ry)
            }
        }
        guard minX.isFinite else { return nil }
        return CGRectValue(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// All retouching of a photo, applied first (before any other edit).
public struct RetouchSettings: Codable, Equatable, Sendable {
    public var operations: [RetouchOperation] = []
    /// 0...100, removes red pupils on every detected face.
    public var redEye: Double = 0

    public init() {}

    public var isIdentity: Bool { operations.isEmpty && redEye == 0 }
}
