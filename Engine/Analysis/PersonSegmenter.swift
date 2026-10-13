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
        // Keep the mask small in memory (≤ 1024 px); it's stretched over the photo lazily.
        let small = RenderContext.materialize(ImageSource.scaled(raw, maxDimension: 1024), context: context)
        let extent = image.extent
        return small
            .transformed(by: CGAffineTransform(scaleX: extent.width / small.extent.width, y: extent.height / small.extent.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
    }
}
