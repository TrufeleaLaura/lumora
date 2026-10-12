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
    private let feedback = UISelectionFeedbackGenerator()

    private var span: Double { range.upperBound - range.lowerBound }

    private func fraction(_ v: Double) -> CGFloat {
        CGFloat((v - range.lowerBound) / span)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let thumbX = fraction(value) * width
            let originX = fraction(origin) * width
            ZStack(alignment: .leading) {
                if let trackGradient {
                    Capsule()
                        .fill(LinearGradient(gradient: trackGradient, startPoint: .leading, endPoint: .trailing))
                        .frame(height: 6)
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(height: 3)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: abs(thumbX - originX), height: 3)
                        .offset(x: min(thumbX, originX))
                }
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: thumbX - 11)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { drag in
                        if dragStartValue == nil {
                            dragStartValue = value
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
