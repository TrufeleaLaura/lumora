import LumoraCore
import SwiftUI

/// 3-way color grading: a hue/saturation wheel per tonal range, plus luminance, blending and balance.
struct GradingPanel: View {
    @ObservedObject var session: EditorSession
    @State private var range: AdjustmentCatalog.GradingRange = .midtones

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Range", selection: $range) {
                ForEach(AdjustmentCatalog.GradingRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 6) {
                    ColorWheel(
                        hue: session.binding(range.keyPath.appending(path: \GradingWheel.hue)),
                        saturation: session.binding(range.keyPath.appending(path: \GradingWheel.saturation)),
                        onEditingChanged: { editing in
                            if editing {
                                session.beginChange()
                            } else {
                                session.endChange(label: "\(range.title) color")
                            }
                        }
                    )
                    .frame(width: 118, height: 118)

                    let wheel = session.document[keyPath: range.keyPath]
                    Text("\(Int(wheel.hue.rounded()))° · \(Int(wheel.saturation.rounded()))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Darkroom.stone)
                    Button {
                        session.perform("Reset \(range.title.lowercased()) grading") {
                            $0[keyPath: range.keyPath] = GradingWheel()
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .accessibilityLabel("Reset \(range.title.lowercased())")
                }

                SliderList(session: session, specs: [AdjustmentCatalog.gradingWheelSliders(range)[2]] + AdjustmentCatalog.grading.sliders)
            }
        }
    }
}

/// Hue (angle) / saturation (distance from center) picker.
struct ColorWheel: View {
    @Binding var hue: Double
    @Binding var saturation: Double
    var onEditingChanged: (Bool) -> Void

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            let radius = diameter / 2
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let angle = hue * .pi / 180
            let distance = CGFloat(saturation / 100) * radius
            let knob = CGPoint(x: center.x + CGFloat(cos(angle)) * distance, y: center.y + CGFloat(sin(angle)) * distance)

            ZStack {
                Circle()
                    .fill(AngularGradient(gradient: .hueSpectrum, center: .center))
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.55), Color(white: 0.55).opacity(0)], center: .center, startRadius: 0, endRadius: radius))
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                    .position(x: knob.x - (geometry.size.width - diameter) / 2, y: knob.y - (geometry.size.height - diameter) / 2)
            }
            .frame(width: diameter, height: diameter)
            .position(center)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let dx = drag.location.x - radius
                        let dy = drag.location.y - radius
                        var degrees = atan2(Double(dy), Double(dx)) * 180 / .pi
                        if degrees < 0 { degrees += 360 }
                        hue = degrees
                        saturation = min(1, Double(hypot(dx, dy) / radius)) * 100
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
    }
}
