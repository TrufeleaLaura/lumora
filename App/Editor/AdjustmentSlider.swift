import LumoraCore
import SwiftUI

/// One labelled adjustment slider. Double-tap the label row to reset.
struct AdjustmentSlider: View {
    let spec: SliderSpec
    @Binding var value: Double
    var onEditingChanged: (Bool) -> Void
    var onReset: () -> Void

    private var isChanged: Bool { abs(value - spec.defaultValue) > 0.0001 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(spec.title)
                    .font(.subheadline)
                Spacer()
                Text(spec.formatted(value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(isChanged ? Theme.accent : Color.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onReset)

            Slider(value: $value, in: spec.range, onEditingChanged: onEditingChanged)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spec.title)
        .accessibilityValue(spec.formatted(value))
    }
}
