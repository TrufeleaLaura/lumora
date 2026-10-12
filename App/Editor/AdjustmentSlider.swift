import LumoraCore
import SwiftUI

/// One labelled adjustment slider. Double-tap the label row to reset.
struct AdjustmentSlider: View {
    let spec: SliderSpec
    @Binding var value: Double
    var swatch: Color?
    var trackGradient: Gradient?
    var onEditingChanged: (Bool) -> Void
    var onReset: () -> Void

    private var isChanged: Bool { abs(value - spec.defaultValue) > 0.0001 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if let swatch {
                    Circle()
                        .fill(swatch)
                        .frame(width: 10, height: 10)
                }
                Text(spec.title)
                    .font(.subheadline)
                Spacer()
                Text(spec.formatted(value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(isChanged ? Theme.accent : Color.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onReset)

            LumoraSlider(
                value: $value,
                range: spec.range,
                origin: spec.isBipolar ? 0 : spec.defaultValue,
                trackGradient: trackGradient,
                onEditingChanged: onEditingChanged
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spec.title)
        .accessibilityValue(spec.formatted(value))
    }
}

/// A scrolling list of sliders bound to the session's document.
struct SliderList: View {
    @ObservedObject var session: EditorSession
    let specs: [SliderSpec]
    var swatches: [String: Color] = [:]
    var gradients: [String: Gradient] = [:]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(specs) { spec in
                AdjustmentSlider(
                    spec: spec,
                    value: session.binding(spec.keyPath),
                    swatch: swatches[spec.id],
                    trackGradient: gradients[spec.id],
                    onEditingChanged: { editing in
                        if editing {
                            session.beginChange()
                        } else {
                            let value = session.document[keyPath: spec.keyPath]
                            session.endChange(label: "\(spec.title) \(spec.formatted(value))")
                        }
                    },
                    onReset: { session.reset(spec) }
                )
            }
        }
    }
}
