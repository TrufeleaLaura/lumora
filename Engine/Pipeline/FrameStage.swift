import CoreImage
import Foundation
import LumoraCore
import UIKit

extension RenderPipeline {
    /// Date stamp, then a border or retro frame around the photo (changes the output size).
    func applyFrame(_ frame: FrameSettings, to input: CIImage) -> CIImage {
        guard !frame.isIdentity else { return input }
        // Work with the photo at the origin.
        var content = input.transformed(by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY))
        let contentExtent = content.extent
        let w = contentExtent.width, h = contentExtent.height
        let short = min(w, h)

        if frame.style == .vhs {
            content = vhs(content)
        }
        if frame.dateStamp {
            content = dateStamp(frame, on: content, vcr: frame.style == .vhs)
        }

        let layout = FrameLayout.layout(frame, contentWidth: Double(w), contentHeight: Double(h))
        let outer = CGRect(x: 0, y: 0, width: CGFloat(layout.width), height: CGFloat(layout.height))
        let origin = CGPoint(x: CGFloat(layout.content.x), y: CGFloat(layout.content.y))
        let placed = content.transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))

        switch frame.style {
        case .none, .vhs:
            return content
        case .border:
            let color = frame.color
            let canvas = CIImage(color: CIColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue))).cropped(to: outer)
            return placed.composited(over: canvas)
        case .polaroid:
            let paper = paperCanvas(outer, base: frame.color == .white ? RGBColor.cream : frame.color)
            // A faint inner shadow where the print meets the frame.
            let edge = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.18))
                .cropped(to: placed.extent.insetBy(dx: -short * 0.004, dy: -short * 0.004))
            let soft = GuidedFilter.gaussian(edge.composited(over: CIImage(color: .clear).cropped(to: outer)), radius: short * 0.004)
            return placed.composited(over: soft.composited(over: paper)).cropped(to: outer)
        case .film:
            return filmStrip(placed, outer: outer, content: placed.extent)
        case .super8:
            return super8(placed, outer: outer, content: placed.extent)
        }
    }

    // MARK: - Pieces

    private func paperCanvas(_ rect: CGRect, base: RGBColor) -> CIImage {
        let longSide = max(rect.width, rect.height)
        let texture = Kernels.grungeTexture.apply(
            extent: rect,
            roiCallback: { _, r in r },
            arguments: [CIVector(x: 7, y: longSide * 0.05, z: max(1, longSide * 0.0008), w: 0)]
        ) ?? Self.white(rect)
        return texture.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.12 * CGFloat(base.red), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0.12 * CGFloat(base.green), y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0.12 * CGFloat(base.blue), y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0.94 * CGFloat(base.red), y: 0.94 * CGFloat(base.green), z: 0.94 * CGFloat(base.blue), w: 0),
        ]).cropped(to: rect)
    }

    private func roundedRect(_ rect: CGRect, radius: CGFloat, color: CIColor) -> CIImage {
        let mask = Kernels.roundedMask.apply(
            extent: rect.insetBy(dx: -2, dy: -2),
            roiCallback: { _, r in r },
            arguments: [CIVector(x: rect.minX, y: rect.minY, z: rect.width, w: rect.height), Float(radius), Float(1)]
        ) ?? CIImage.empty()
        // White premultiplied mask → tinted.
        return mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: color.red, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: color.green, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: color.blue, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
    }

    private func filmStrip(_ placed: CIImage, outer: CGRect, content: CGRect) -> CIImage {
        var canvas = CIImage(color: CIColor(red: 0.035, green: 0.03, blue: 0.028)).cropped(to: outer)
        let horizontal = content.width >= content.height
        let strip = horizontal ? content.minY : content.minX
        let holeColor = CIColor(red: 0.93, green: 0.9, blue: 0.84)
        let along = horizontal ? outer.width : outer.height
        let holeLong = strip * 0.36, holeShort = strip * 0.26
        let pitch = holeLong * 1.9
        let count = Int(along / pitch)
        let start = (along - CGFloat(count) * pitch) / 2 + pitch / 2
        for i in 0..<count {
            let c = start + CGFloat(i) * pitch
            for side in 0..<2 {
                let center = side == 0 ? strip * 0.5 : (horizontal ? outer.height : outer.width) - strip * 0.5
                let rect = horizontal
                    ? CGRect(x: c - holeShort / 2, y: center - holeLong / 2 + holeLong * 0.1, width: holeShort, height: holeLong * 0.8)
                    : CGRect(x: center - holeLong / 2 + holeLong * 0.1, y: c - holeShort / 2, width: holeLong * 0.8, height: holeShort)
                canvas = roundedRect(rect, radius: holeShort * 0.2, color: holeColor).composited(over: canvas)
            }
        }
        // Edge printing.
        let ink = UIColor(red: 0.95, green: 0.62, blue: 0.2, alpha: 0.9)
        let font = TextRenderer.font(.mono, size: strip * 0.15, weight: .bold)
        let labels = ["LUMORA 400", "12  ▸  12A"]
        let gap = strip * 0.02
        for (index, label) in labels.enumerated() {
            guard var text = TextRenderer.textImage(label, font: font, color: ink) else { continue }
            if !horizontal {
                text = text.transformed(by: CGAffineTransform(rotationAngle: .pi / 2))
            }
            let t = text.extent
            // Printed between the sprocket holes and the picture.
            let position: CGPoint
            if horizontal {
                position = index == 0
                    ? CGPoint(x: content.minX + content.width * 0.1, y: content.maxY + gap)
                    : CGPoint(x: content.maxX - content.width * 0.1 - t.width, y: content.minY - gap - t.height)
            } else {
                position = index == 0
                    ? CGPoint(x: content.minX - gap - t.width, y: content.minY + content.height * 0.1)
                    : CGPoint(x: content.maxX + gap, y: content.maxY - content.height * 0.1 - t.height)
            }
            canvas = text.transformed(by: CGAffineTransform(translationX: position.x - t.minX, y: position.y - t.minY)).composited(over: canvas)
        }
        let radius = min(content.width, content.height) * 0.012
        let mask = Kernels.roundedMask.apply(
            extent: content,
            roiCallback: { _, r in r },
            arguments: [CIVector(x: content.minX, y: content.minY, z: content.width, w: content.height), Float(radius), Float(1)]
        ) ?? Self.white(content)
        return placed.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: canvas, kCIInputMaskImageKey: mask]).cropped(to: outer)
    }

    private func super8(_ placed: CIImage, outer: CGRect, content: CGRect) -> CIImage {
        var canvas = CIImage(color: CIColor(red: 0.02, green: 0.02, blue: 0.02)).cropped(to: outer)
        let short = min(content.width, content.height)
        // One sprocket hole on the left.
        let holeWidth = (content.minX - outer.minX) * 0.45
        let holeHeight = short * 0.16
        let hole = CGRect(x: outer.minX + (content.minX - outer.minX - holeWidth) * 0.45, y: content.midY - holeHeight / 2, width: holeWidth, height: holeHeight)
        canvas = roundedRect(hole, radius: holeWidth * 0.25, color: CIColor(red: 0.9, green: 0.88, blue: 0.82)).composited(over: canvas)
        // Rounded gate with a soft, darker edge.
        let radius = short * 0.07
        let mask = Kernels.roundedMask.apply(
            extent: content,
            roiCallback: { _, r in r },
            arguments: [CIVector(x: content.minX, y: content.minY, z: content.width, w: content.height), Float(radius), Float(short * 0.006)]
        ) ?? Self.white(content)
        let vignette = Kernels.roundedMask.apply(
            extent: content,
            roiCallback: { _, r in r },
            arguments: [CIVector(x: content.minX + short * 0.05, y: content.minY + short * 0.05, z: content.width - short * 0.1, w: content.height - short * 0.1), Float(radius), Float(short * 0.08)]
        ) ?? Self.white(content)
        let shaded = Kernels.multiplyBlend.apply(placed, vignette.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.45, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0.45, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0.45, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0.55, y: 0.55, z: 0.55, w: 1),
        ]), Float(1))
        return shaded.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: canvas, kCIInputMaskImageKey: mask]).cropped(to: outer)
    }

    private func vhs(_ content: CIImage) -> CIImage {
        let extent = content.extent
        let longSide = max(extent.width, extent.height)
        let smeared = content.clampedToExtent()
            .applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: longSide * 0.006, kCIInputAngleKey: 0])
            .cropped(to: extent)
        var image = Kernels.vhs.apply(
            extent: extent,
            roiCallback: { _, r in r },
            arguments: [content, smeared, CIVector(x: 1, y: max(1.5, extent.height / 240), z: extent.minY + extent.height * 0.07, w: extent.height * 0.018)]
        ) ?? content
        // On-screen display.
        let font = TextRenderer.font(.mono, size: extent.height * 0.05, weight: .bold)
        let white = UIColor(white: 0.97, alpha: 0.92)
        let glow = UIColor(white: 1, alpha: 0.5)
        let margin = min(extent.width, extent.height) * 0.06
        if let play = TextRenderer.textImage("PLAY ▶", font: font, color: white, glow: glow) {
            let t = play.extent
            image = play.transformed(by: CGAffineTransform(translationX: extent.minX + margin - t.minX, y: extent.maxY - margin - t.maxY)).composited(over: image)
        }
        if let speed = TextRenderer.textImage("SP", font: font, color: white, glow: glow) {
            let t = speed.extent
            image = speed.transformed(by: CGAffineTransform(translationX: extent.maxX - margin - t.maxX, y: extent.maxY - margin - t.maxY)).composited(over: image)
        }
        return image.cropped(to: extent)
    }

    /// Orange digital date (or a white VCR date) in the photo's corner.
    private func dateStamp(_ frame: FrameSettings, on content: CIImage, vcr: Bool) -> CIImage {
        let extent = content.extent
        let short = min(extent.width, extent.height)
        let text = frame.dateText.isEmpty ? Self.stampText(for: Date()) : frame.dateText
        let color = vcr ? UIColor(white: 0.97, alpha: 0.92) : UIColor(red: 1, green: 0.55, blue: 0.16, alpha: 0.95)
        let glow = vcr ? UIColor(white: 1, alpha: 0.5) : UIColor(red: 1, green: 0.35, blue: 0.05, alpha: 0.85)
        let font = TextRenderer.font(.mono, size: short * (vcr ? 0.05 : 0.045), weight: .bold)
        guard let stamp = TextRenderer.textImage(text, font: font, color: color, kerning: short * 0.004, glow: glow) else { return content }
        let t = stamp.extent
        let margin = short * 0.05
        let position = vcr
            ? CGPoint(x: extent.minX + margin - t.minX, y: extent.minY + margin - t.minY)
            : CGPoint(x: extent.maxX - margin - t.maxX, y: extent.minY + margin - t.minY)
        return stamp.transformed(by: CGAffineTransform(translationX: position.x, y: position.y)).composited(over: content).cropped(to: extent)
    }

    /// Point-and-shoot style date: "'26 10 13".
    public static func stampText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "''yy MM dd"
        return formatter.string(from: date)
    }
}
