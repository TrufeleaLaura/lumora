import CoreImage
import Foundation
import LumoraCore

/// Lays photos out on a collage or story canvas.
public enum CollageRenderer {
    /// - Parameters:
    ///   - images: one (already edited) image per cell; nil cells stay empty.
    ///   - scale: output scale (1 = the aspect's full pixel size).
    public static func render(_ settings: CollageSettings, images: [CIImage?], crops: [CollageCrop], scale: CGFloat = 1) -> CIImage {
        let size = settings.aspect.pixelSize
        let width = Double(size.width) * Double(scale)
        let height = Double(size.height) * Double(scale)
        let canvasRect = CGRect(x: 0, y: 0, width: width, height: height)
        let background = settings.background
        var canvas = CIImage(color: CIColor(red: CGFloat(background.red), green: CGFloat(background.green), blue: CGFloat(background.blue))).cropped(to: canvasRect)
        let radius = CGFloat(settings.cornerRadius(width: width, height: height))

        for (index, cell) in settings.cellRects(width: width, height: height).enumerated() {
            let cellRect = CGRect(x: cell.x, y: cell.y, width: cell.width, height: cell.height)
            let content: CIImage
            if index < images.count, let image = images[index] {
                let extent = image.extent
                let crop = index < crops.count ? crops[index] : CollageCrop()
                let target = CollageMath.imageRect(imageWidth: Double(extent.width), imageHeight: Double(extent.height), cell: cell, crop: crop)
                let sx = CGFloat(target.width) / extent.width
                let sy = CGFloat(target.height) / extent.height
                content = image
                    .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
                    .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                    .transformed(by: CGAffineTransform(translationX: CGFloat(target.x), y: CGFloat(target.y)))
                    .cropped(to: cellRect)
            } else {
                // Empty cell: a slightly darker shade of the background.
                content = CIImage(color: CIColor(red: CGFloat(background.red) * 0.88, green: CGFloat(background.green) * 0.88, blue: CGFloat(background.blue) * 0.88)).cropped(to: cellRect)
            }
            if radius > 0.5 {
                let mask = Kernels.roundedMask.apply(
                    extent: cellRect,
                    roiCallback: { _, r in r },
                    arguments: [CIVector(x: cellRect.minX, y: cellRect.minY, z: cellRect.width, w: cellRect.height), Float(radius), Float(1)]
                ) ?? RenderPipeline.white(cellRect)
                canvas = content.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: canvas, kCIInputMaskImageKey: mask]).cropped(to: canvasRect)
            } else {
                canvas = content.composited(over: canvas)
            }
        }
        return canvas
    }
}
