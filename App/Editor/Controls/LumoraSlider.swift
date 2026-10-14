import SwiftUI
import UIKit

/// Precision dial: a ruler of tick marks with a fine needle. Dragging moves the value relative to
/// where the finger started (taps don't jump), ticks between `origin` and the value are lit, and
/// a light haptic clicks at every major mark, like a camera dial.
struct LumoraSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Where the lit span starts (0 for ± sliders, the minimum otherwise).
    var origin: Double
    /// Optional gradient drawn under the ruler (e.g. a hue rainbow).
    var trackGradient: Gradient?
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var dragStartValue: Double?
    @State private var isDragging = false
    @State private var lastDetent: Int?
    private let feedback = UISelectionFeedbackGenerator()

    /// Major marks across the range (the origin of ± sliders falls on one).
    private let detents = 10

    private var span: Double { range.upperBound - range.lowerBound }

    private func fraction(_ v: Double) -> CGFloat {
        CGFloat((v - range.lowerBound) / span)
    }

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 6
            let width = max(geometry.size.width - 2 * inset, 1)
            Canvas { context, size in
                drawDial(in: &context, size: size, inset: inset, width: width)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { drag in
                        if dragStartValue == nil {
                            dragStartValue = value
                            isDragging = true
                            lastDetent = detent(of: value)
                            feedback.prepare()
                            onEditingChanged(true)
                        }
                        let start = dragStartValue ?? value
                        let delta = Double(drag.translation.width / max(width, 1)) * span
                        let newValue = min(max(start + delta, range.lowerBound), range.upperBound)
                        let mark = detent(of: newValue)
                        if mark != lastDetent {
                            feedback.selectionChanged()
                            lastDetent = mark
                        }
                        value = newValue
                    }
                    .onEnded { _ in
                        dragStartValue = nil
                        isDragging = false
                        lastDetent = nil
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 30)
        .animation(Darkroom.ease, value: isDragging)
        .accessibilityElement()
        .accessibilityAdjustableAction { direction in
            let step = span / 100
            onEditingChanged(true)
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
            onEditingChanged(false)
        }
    }

    /// The nearest major mark to a value.
    private func detent(of v: Double) -> Int {
        Int((fraction(v) * CGFloat(detents)).rounded())
    }

    private func drawDial(in context: inout GraphicsContext, size: CGSize, inset: CGFloat, width: CGFloat) {
        let baseline: CGFloat = 17
        let thumbX = inset + fraction(value) * width
        let originX = inset + fraction(origin) * width
        let lo = min(thumbX, originX) - 0.5
        let hi = max(thumbX, originX) + 0.5
        let changed = abs(thumbX - originX) > 0.5

        if let trackGradient {
            let strip = CGRect(x: inset, y: baseline + 4, width: width, height: 4)
            context.fill(
                Path(roundedRect: strip, cornerRadius: 1),
                with: .linearGradient(trackGradient, startPoint: CGPoint(x: strip.minX, y: 0), endPoint: CGPoint(x: strip.maxX, y: 0))
            )
        }

        // Ruler: minor ticks, majors every fifth, all aligned on the baseline.
        let minorPerMajor = 5
        let ticks = detents * minorPerMajor
        for index in 0...ticks {
            let x = inset + CGFloat(index) / CGFloat(ticks) * width
            let isMajor = index % minorPerMajor == 0
            let height: CGFloat = isMajor ? 9 : 5
            let lit = trackGradient == nil && changed && x >= lo && x <= hi
            let rect = CGRect(x: x - 0.5, y: baseline - height, width: 1, height: height)
            context.fill(Path(rect), with: .color(lit ? Darkroom.cream : Darkroom.muted))
        }

        // Origin of ± sliders: a taller cream mark.
        if origin > range.lowerBound, origin < range.upperBound {
            let rect = CGRect(x: originX - 0.5, y: baseline - 13, width: 1, height: 13)
            context.fill(Path(rect), with: .color(Darkroom.cream.opacity(0.8)))
        }

        // Needle and pointer.
        let needleColor = trackGradient == nil ? Darkroom.safelight : Darkroom.cream
        let needleWidth: CGFloat = isDragging ? 2 : 1.5
        let needle = CGRect(x: thumbX - needleWidth / 2, y: 1, width: needleWidth, height: baseline - 1)
        context.fill(Path(needle), with: .color(needleColor))
        var pointer = Path()
        let tip = baseline + (trackGradient == nil ? 3 : 8)
        pointer.move(to: CGPoint(x: thumbX, y: tip))
        pointer.addLine(to: CGPoint(x: thumbX - 4, y: tip + 6))
        pointer.addLine(to: CGPoint(x: thumbX + 4, y: tip + 6))
        pointer.closeSubpath()
        context.fill(pointer, with: .color(needleColor))
    }
}

extension Gradient {
    /// Full hue circle, red → red.
    static let hueSpectrum = Gradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
        Color(hue: $0, saturation: 0.9, brightness: 0.95)
    })
}
