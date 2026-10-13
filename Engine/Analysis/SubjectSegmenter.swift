import CoreImage
import CoreVideo
import Foundation
import Vision

/// Foreground objects found by Vision ("lift subject"): soft masks for all of them or for
/// the ones under tapped points.
public final class SubjectAnalysis: @unchecked Sendable {
    private let observation: VNInstanceMaskObservation
    private let handler: VNImageRequestHandler
    private let extent: CGRect
    private let context: CIContext
    /// Instance label per pixel of Vision's low-resolution label map (rows top-down, 0 = background).
    private let labels: [UInt8]
    private let labelWidth: Int
    private let labelHeight: Int
    private let lock = NSLock()
    private var cache: [IndexSet: CIImage] = [:]

    init(observation: VNInstanceMaskObservation, handler: VNImageRequestHandler, extent: CGRect, context: CIContext) {
        self.observation = observation
        self.handler = handler
        self.extent = extent
        self.context = context
        let buffer = observation.instanceMask
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var labels = [UInt8](repeating: 0, count: width * height)
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    labels[y * width + x] = bytes[y * rowBytes + x]
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        self.labels = labels
        self.labelWidth = width
        self.labelHeight = height
    }

    public var instanceCount: Int { observation.allInstances.count }

    /// Soft mask of every foreground object over the analyzed image's extent.
    public var allMask: CIImage? { mask(instances: observation.allInstances) }

    /// Instances under normalized points (y up); looks a little around each point.
    public func instances(at points: [SIMD2<Double>]) -> IndexSet {
        var result = IndexSet()
        guard labelWidth > 0, labelHeight > 0 else { return result }
        for point in points {
            let cx = Int(point.x * Double(labelWidth))
            let cy = Int((1 - point.y) * Double(labelHeight))
            var found: UInt8 = 0
            search: for radius in 0...3 {
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let x = cx + dx, y = cy + dy
                        guard x >= 0, y >= 0, x < labelWidth, y < labelHeight else { continue }
                        let label = labels[y * labelWidth + x]
                        if label != 0 {
                            found = label
                            break search
                        }
                    }
                }
            }
            if found != 0 { result.insert(Int(found)) }
        }
        return result
    }

    /// Soft mask of the given instances (cached).
    public func mask(instances: IndexSet) -> CIImage? {
        guard !instances.isEmpty else { return nil }
        lock.lock()
        if let cached = cache[instances] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard let buffer = try? observation.generateScaledMaskForImage(forInstances: instances, from: handler) else { return nil }
        let raw = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
        let scaled = raw
            .transformed(by: CGAffineTransform(scaleX: extent.width / max(raw.extent.width, 1), y: extent.height / max(raw.extent.height, 1)))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
        // Single-channel buffers read as (v, 0, 0): spread to gray so every channel holds the mask.
        let gray = scaled.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        let result = RenderContext.materialize(gray, context: context)
        lock.lock()
        if cache.count > 16 { cache.removeAll() }
        cache[instances] = result
        lock.unlock()
        return result
    }
}

public enum SubjectSegmenter {
    /// Runs Vision's foreground instance segmentation, or nil when unavailable (e.g. simulator).
    public static func analyze(_ image: CIImage, context: CIContext = RenderContext.analysis) -> SubjectAnalysis? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
        return SubjectAnalysis(observation: observation, handler: handler, extent: image.extent, context: context)
    }
}
