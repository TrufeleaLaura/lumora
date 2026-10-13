import CoreImage
import Foundation
import LumoraCore
import UIKit

/// Renders text and SF Symbol stickers into images (premultiplied, sRGB, origin at 0, 0).
enum TextRenderer {
    private static let cache = NSCache<NSString, CIImage>()

    static func font(_ font: TextFont, size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
        if let name = font.fontName, let custom = UIFont(name: name, size: size) {
            return custom
        }
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let design: UIFontDescriptor.SystemDesign
        switch font {
        case .serif: design = .serif
        case .rounded: design = .rounded
        case .mono: design = .monospaced
        default: design = .default
        }
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func uiColor(_ color: RGBColor, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: alpha)
    }

    /// A text layer (or sticker) at `pixelSize` (font size in output pixels).
    static func image(_ layer: TextLayer, pixelSize: CGFloat) -> CIImage? {
        let size = max(4, (pixelSize * 2).rounded() / 2)
        var copy = layer
        copy.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        copy.position = .zero
        copy.rotation = 0
        copy.opacity = 100
        let fingerprint = (try? JSONEncoder().encode(copy)).map { $0.base64EncodedString() } ?? layer.text
        let key = "\(fingerprint)|\(size)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let result: CIImage?
        if let symbol = layer.symbol {
            result = symbolImage(symbol, pixelSize: size, color: layer.color, shadow: layer.shadow)
        } else {
            let alignment: NSTextAlignment
            switch layer.alignment {
            case .left: alignment = .left
            case .center: alignment = .center
            case .right: alignment = .right
            }
            result = textImage(
                layer.uppercase ? layer.text.uppercased() : layer.text,
                font: font(layer.font, size: size),
                color: uiColor(layer.color),
                kerning: CGFloat(layer.spacing / 100) * size * 0.3,
                alignment: alignment,
                shadow: layer.shadow,
                glow: layer.glow ? uiColor(layer.color, alpha: 0.9) : nil,
                outline: layer.outline ? uiColor(layer.outlineColor) : nil,
                background: layer.background ? uiColor(layer.backgroundColor, alpha: CGFloat(layer.backgroundOpacity / 100)) : nil,
                lineSpacing: CGFloat(layer.lineSpacing / 100) * size * 0.6
            )
        }
        if let result { cache.setObject(result, forKey: key) }
        return result
    }

    static func textImage(_ text: String, font: UIFont, color: UIColor, kerning: CGFloat = 0, alignment: NSTextAlignment = .center, shadow: Bool = false, glow: UIColor? = nil, outline: UIColor? = nil, background: UIColor? = nil, lineSpacing: CGFloat = 0) -> CIImage? {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineSpacing = lineSpacing
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: kerning,
            .paragraphStyle: paragraph,
        ]
        if let outline {
            // Negative width: fill and stroke.
            attributes[.strokeColor] = outline
            attributes[.strokeWidth] = -4.0
        }
        let string = NSAttributedString(string: text.isEmpty ? " " : text, attributes: attributes)
        let bounds = string.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).integral
        let pad = ceil(font.pointSize * (glow != nil ? 0.6 : 0.35))
        let canvas = CGSize(width: bounds.width + 2 * pad, height: bounds.height + 2 * pad)
        guard canvas.width > 0, canvas.height > 0, canvas.width * canvas.height < 80_000_000 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let textRect = CGRect(x: pad, y: pad, width: bounds.width, height: bounds.height)
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            if let background {
                // A rounded label hugging the text.
                let box = textRect.insetBy(dx: -font.pointSize * 0.35, dy: -font.pointSize * 0.12)
                background.setFill()
                UIBezierPath(roundedRect: box, cornerRadius: font.pointSize * 0.28).fill()
            }
            if shadow {
                context.cgContext.setShadow(offset: CGSize(width: 0, height: font.pointSize * 0.04), blur: font.pointSize * 0.15, color: UIColor.black.withAlphaComponent(0.55).cgColor)
            } else if let glow {
                context.cgContext.setShadow(offset: .zero, blur: font.pointSize * 0.5, color: glow.cgColor)
                // Twice, for a stronger neon halo.
                string.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            }
            string.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        return image.cgImage.map { CIImage(cgImage: $0) }
    }

    static func symbolImage(_ name: String, pixelSize: CGFloat, color: RGBColor, shadow: Bool) -> CIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: pixelSize, weight: .regular)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration)?.withTintColor(uiColor(color), renderingMode: .alwaysOriginal) else { return nil }
        let pad = ceil(pixelSize * 0.3)
        let canvas = CGSize(width: symbol.size.width + 2 * pad, height: symbol.size.height + 2 * pad)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            if shadow {
                context.cgContext.setShadow(offset: CGSize(width: 0, height: pixelSize * 0.04), blur: pixelSize * 0.15, color: UIColor.black.withAlphaComponent(0.55).cgColor)
            }
            symbol.draw(at: CGPoint(x: pad, y: pad))
        }
        return image.cgImage.map { CIImage(cgImage: $0) }
    }

    /// Scales a premultiplied image's opacity.
    static func faded(_ image: CIImage, opacity: CGFloat) -> CIImage {
        guard opacity < 0.999 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: opacity, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: opacity, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: opacity, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity),
        ])
    }

    /// Places `image` centered at `center` (pixels), rotated by `degrees` (counterclockwise).
    static func place(_ image: CIImage, center: CGPoint, degrees: Double) -> CIImage {
        let r = image.extent
        let transform = CGAffineTransform(translationX: -r.midX, y: -r.midY)
            .concatenating(CGAffineTransform(rotationAngle: CGFloat(degrees * .pi / 180)))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
        return image.transformed(by: transform)
    }
}

extension RenderPipeline {
    /// Text and stickers over the (cropped) photo.
    func applyTexts(_ texts: [TextLayer], to input: CIImage) -> CIImage {
        guard !texts.isEmpty else { return input }
        var image = input
        let extent = input.extent
        for layer in texts where layer.opacity > 0 {
            guard let rendered = TextRenderer.image(layer, pixelSize: CGFloat(layer.size) * extent.width) else { continue }
            let center = CGPoint(x: extent.minX + CGFloat(layer.position.x) * extent.width, y: extent.minY + CGFloat(layer.position.y) * extent.height)
            let placed = TextRenderer.place(TextRenderer.faded(rendered, opacity: CGFloat(layer.opacity / 100)), center: center, degrees: layer.rotation)
            image = placed.composited(over: image).cropped(to: extent)
        }
        return image
    }
}
