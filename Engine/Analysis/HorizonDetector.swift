import CoreImage
import Foundation
import Vision

public enum HorizonDetector {
    /// Tilt of the photo's horizon in degrees (positive = the horizon rises to the right),
    /// or nil when Vision finds no horizon. Rotating clockwise by this angle levels the photo.
    public static func tilt(of image: CIImage) -> Double? {
        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        return Double(observation.angle) * 180 / .pi
    }
}
