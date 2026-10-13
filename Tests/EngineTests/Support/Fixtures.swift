import CoreImage
import Foundation
@testable import LumoraEngine

private final class FixtureBundleMarker {}

/// Real photos from Fixtures/Photos (see CREDITS.md there).
enum Fixtures {
    static func photo(_ name: String) -> CIImage {
        let bundle = Bundle(for: FixtureBundleMarker.self)
        guard let url = bundle.url(forResource: name, withExtension: "jpg", subdirectory: "Photos")
                ?? bundle.url(forResource: name, withExtension: "jpg"),
              let data = try? Data(contentsOf: url),
              let source = ImageSource(data: data) else {
            fatalError("Missing fixture photo \(name)")
        }
        return source.original
    }

    /// Crop around a normalized rect (y up), scaled so the long side is `size` pixels.
    static func crop(_ image: CIImage, normalized rect: (x: Double, y: Double, width: Double, height: Double), size: CGFloat = 420) -> CIImage {
        let extent = image.extent
        let pixels = CGRect(
            x: extent.minX + CGFloat(rect.x) * extent.width,
            y: extent.minY + CGFloat(rect.y) * extent.height,
            width: CGFloat(rect.width) * extent.width,
            height: CGFloat(rect.height) * extent.height
        ).intersection(extent)
        let scale = size / max(pixels.width, pixels.height)
        return image.cropped(to: pixels)
            .transformed(by: CGAffineTransform(translationX: -pixels.minX, y: -pixels.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}
