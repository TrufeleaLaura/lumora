import CoreImage
import CoreVideo
import Foundation
import Vision

/// People masks from Vision's person segmentation.
public enum PersonSegmenter {
    /// Soft person mask (white = person) stretched over the image's extent, or nil on failure.
    public static func mask(for image: CIImage, context: CIContext = RenderContext.analysis) -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let buffer = request.results?.first?.pixelBuffer else { return nil }
        let raw = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
        let extent = image.extent
        let scaled = raw.transformed(by: CGAffineTransform(scaleX: extent.width / raw.extent.width, y: extent.height / raw.extent.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
        return RenderContext.materialize(scaled, context: context)
    }
}
