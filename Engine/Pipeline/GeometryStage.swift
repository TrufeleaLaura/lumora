import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import LumoraCore

extension RenderPipeline {
    /// Flips, quarter turns, perspective, straightening and (optionally) the crop.
    /// Every step is resolution-independent, so preview and export match.
    public func applyGeometry(_ geometry: GeometrySettings, to input: CIImage, includeCrop: Bool = true) -> CIImage {
        guard !geometry.isIdentity else { return input }
        var image = ImageSource.normalized(input)

        // Flips and quarter turns.
        if geometry.flipHorizontal {
            image = ImageSource.normalized(image.transformed(by: CGAffineTransform(scaleX: -1, y: 1)))
        }
        if geometry.flipVertical {
            image = ImageSource.normalized(image.transformed(by: CGAffineTransform(scaleX: 1, y: -1)))
        }
        let turns = ((geometry.quarterTurns % 4) + 4) % 4
        if turns != 0 {
            // Clockwise on screen = negative angle in Core Image's y-up space.
            image = ImageSource.normalized(image.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(turns) * .pi / 2)))
        }

        // Perspective: a source trapezoid is rectified onto the full frame (no empty areas).
        if geometry.vertical != 0 || geometry.horizontal != 0 {
            let extent = image.extent
            let w = extent.width
            let h = extent.height
            let v = CGFloat(geometry.vertical / 100) * 0.22
            let hz = CGFloat(geometry.horizontal / 100) * 0.22
            var topLeft = CGPoint(x: 0, y: h)
            var topRight = CGPoint(x: w, y: h)
            var bottomLeft = CGPoint(x: 0, y: 0)
            var bottomRight = CGPoint(x: w, y: 0)
            if v > 0 {
                topLeft.x += v * w
                topRight.x -= v * w
            } else if v < 0 {
                bottomLeft.x -= v * w
                bottomRight.x += v * w
            }
            if hz > 0 {
                topRight.y -= hz * h
                bottomRight.y += hz * h
            } else if hz < 0 {
                topLeft.y += hz * h
                bottomLeft.y -= hz * h
            }
            let filter = CIFilter.perspectiveCorrection()
            filter.inputImage = image.clampedToExtent()
            filter.topLeft = topLeft
            filter.topRight = topRight
            filter.bottomLeft = bottomLeft
            filter.bottomRight = bottomRight
            if let output = filter.outputImage, output.extent.width > 1, output.extent.height > 1, !output.extent.isInfinite {
                let normalized = ImageSource.normalized(output)
                image = normalized
                    .transformed(by: CGAffineTransform(scaleX: w / normalized.extent.width, y: h / normalized.extent.height))
                    .cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }

        // Straighten: rotate around the center and scale up just enough to hide the corners.
        if geometry.straighten != 0 {
            let extent = image.extent
            let scale = CGFloat(GeometryMath.coverScale(width: Double(extent.width), height: Double(extent.height), degrees: geometry.straighten))
            let angle = -CGFloat(geometry.straighten) * .pi / 180
            let transform = CGAffineTransform(translationX: -extent.midX, y: -extent.midY)
                .concatenating(CGAffineTransform(rotationAngle: angle))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: extent.midX, y: extent.midY))
            image = image.clampedToExtent().transformed(by: transform).cropped(to: extent)
        }

        if includeCrop && !geometry.crop.isFull {
            let extent = image.extent
            let crop = geometry.crop.clamped(minimumSize: 0.01)
            let rect = CGRect(
                x: extent.minX + CGFloat(crop.x) * extent.width,
                y: extent.minY + CGFloat(crop.y) * extent.height,
                width: CGFloat(crop.width) * extent.width,
                height: CGFloat(crop.height) * extent.height
            ).integral.intersection(extent)
            image = ImageSource.normalized(image.cropped(to: rect))
        }
        return image
    }
}
