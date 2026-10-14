import SwiftUI
import UIKit

/// Precision slider: dragging moves the value relative to where the finger started
/// (taps don't jump), the fill grows from `origin`, and a light haptic ticks at the origin.
struct LumoraSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Where the fill starts (0 for ± sliders, the minimum otherwise).
    var origin: Double
    /// Optional gradient drawn as the track (e.g. a hue rainbow).
    var trackGradient: Gradient?
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var dragStartValue: Double?
    @State private var isDragging = false
    private let feedback = UISelectionFeedbackGenerator()

    private var span: Double { range.upperBound - range.lowerBound }

    private func fraction(_ v: Double) -> CGFloat {
        CGFloat((v - range.lowerBound) / span)
    }

    var body: some View {
        GeometryReader { geometry in
            // The track is inset by the thumb's radius so the thumb never sticks out (and gets
            // clipped by a scroll view) at either end.
            let inset: CGFloat = 11
            let width = max(geometry.size.width - 2 * inset, 1)
            let thumbX = inset + fraction(value) * width
            let originX = inset + fraction(origin) * width
            ZStack(alignment: .leading) {
                if let trackGradient {
                    Capsule()
                        .fill(LinearGradient(gradient: trackGradient, startPoint: .leading, endPoint: .trailing))
                        .frame(width: width, height: 6)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                        .offset(x: inset)
                } else {
                    Capsule()
                        .fill(Aura.surfaceRaised)
                        .overlay(Capsule().strokeBorder(Aura.hairline, lineWidth: 0.5))
                        .frame(width: width, height: 4)
                        .offset(x: inset)
                    // The origin: a small notch on ± sliders.
                    if origin > range.lowerBound {
                        Capsule()
                            .fill(Aura.textSecondary.opacity(0.5))
                            .frame(width: 2, height: 9)
                            .offset(x: originX - 1)
                    }
                    // The fill: the aura gradient, revealed from the origin.
                    Aura.gradient
                        .frame(width: width, height: 4)
                        .mask(alignment: .leading) {
                            Capsule()
                                .frame(width: max(abs(thumbX - originX), 0.01), height: 4)
                                .offset(x: min(thumbX, originX) - inset)
                        }
                        .shadow(color: Aura.lavender.opacity(isDragging ? 0.8 : 0.45), radius: isDragging ? 6 : 3)
                        .offset(x: inset)
                }
                // The orb.
                ZStack {
                    Circle()
                        .fill(Aura.lavender.opacity(isDragging ? 0.35 : 0))
                        .frame(width: 38, height: 38)
                        .blur(radius: 6)
                    Circle()
                        .fill(Aura.orb)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                        .shadow(color: Aura.lavender.opacity(0.75), radius: isDragging ? 10 : 5)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .scaleEffect(isDragging ? 1.25 : 1)
                }
                .frame(width: 22, height: 22)
                .offset(x: thumbX - 11)
                .animation(Aura.bouncy, value: isDragging)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { drag in
                        if dragStartValue == nil {
                            dragStartValue = value
                            isDragging = true
                            feedback.prepare()
                            onEditingChanged(true)
                        }
                        let start = dragStartValue ?? value
                        let delta = Double(drag.translation.width / max(width, 1)) * span
                        let newValue = min(max(start + delta, range.lowerBound), range.upperBound)
                        if (value - origin) * (newValue - origin) < 0 || (newValue == origin && value != origin) {
                            feedback.selectionChanged()
                        }
                        value = newValue
                    }
                    .onEnded { _ in
                        dragStartValue = nil
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 30)
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
}

extension Gradient {
    /// Full hue circle, red → red.
    static let hueSpectrum = Gradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
        Color(hue: $0, saturation: 0.9, brightness: 0.95)
    })
}
