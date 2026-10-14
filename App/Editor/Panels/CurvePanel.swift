import LumoraCore
import SwiftUI

/// Tone curve: point curves per channel, or parametric region sliders.
struct CurvePanel: View {
    @ObservedObject var session: EditorSession
    @State private var mode = Mode.point
    @State private var channel: CurveChannel = .master

    enum Mode: String, CaseIterable, Identifiable {
        case point = "Point"
        case parametric = "Parametric"
        var id: String { rawValue }
    }

    private func color(for channel: CurveChannel) -> Color {
        switch channel {
        case .master: return .white
        case .red: return Color(red: 1, green: 0.35, blue: 0.35)
        case .green: return Color(red: 0.35, green: 0.9, blue: 0.4)
        case .blue: return Color(red: 0.4, green: 0.6, blue: 1)
        }
    }

    private var pointsBinding: Binding<[CurvePoint]> {
        Binding(
            get: { session.document.curve.points(for: channel) },
            set: { session.document.curve.setPoints($0, for: channel) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer(minLength: 0)

                if mode == .point {
                    ForEach(CurveChannel.allCases) { item in
                        Button {
                            channel = item
                        } label: {
                            Circle()
                                .fill(color(for: item))
                                .frame(width: 18, height: 18)
                                .overlay(Circle().stroke(Darkroom.safelight, lineWidth: channel == item ? 2 : 0).padding(-3))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("\(item.rawValue) curve")
                    }
                    Button {
                        session.perform("Reset \(channel.rawValue) curve") {
                            $0.curve.setPoints(ToneCurveSettings.linear, for: channel)
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.footnote)
                    }
                    .accessibilityLabel("Reset curve")
                }
            }

            if mode == .point {
                CurveEditor(
                    points: pointsBinding,
                    color: color(for: channel),
                    onEditingChanged: { editing in
                        if editing {
                            session.beginChange()
                        } else {
                            session.endChange(label: "\(channel.rawValue.capitalized) curve")
                        }
                    }
                )
                .frame(width: 190, height: 190)
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    SliderList(session: session, specs: AdjustmentCatalog.curveParametric.sliders)
                }
            }
        }
    }
}

/// Interactive point-curve editor (x: input, y: output; 0...1, origin bottom-left).
struct CurveEditor: View {
    @Binding var points: [CurvePoint]
    let color: Color
    var onEditingChanged: (Bool) -> Void

    @State private var dragIndex: Int?
    @State private var isEditing = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.25))
                gridPath(size)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: size.height))
                    path.addLine(to: CGPoint(x: size.width, y: 0))
                }
                .stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                curvePath(size)
                    .stroke(color, lineWidth: 2)
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(index == dragIndex ? Darkroom.safelight : color)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                        .position(position(of: point, in: size))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in handleDrag(drag, size: size) }
                    .onEnded { _ in
                        dragIndex = nil
                        if isEditing {
                            isEditing = false
                            onEditingChanged(false)
                        }
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func position(of point: CurvePoint, in size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(point.x) * size.width, y: (1 - CGFloat(point.y)) * size.height)
    }

    private func normalized(_ location: CGPoint, in size: CGSize) -> (x: Double, y: Double) {
        (Double(location.x / max(size.width, 1)), Double(1 - location.y / max(size.height, 1)))
    }

    private func gridPath(_ size: CGSize) -> Path {
        Path { path in
            for i in 1..<4 {
                let x = size.width * CGFloat(i) / 4
                let y = size.height * CGFloat(i) / 4
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
    }

    private func curvePath(_ size: CGSize) -> Path {
        Path { path in
            let steps = 96
            for step in 0...steps {
                let x = Double(step) / Double(steps)
                let y = ToneCurveMath.evaluate(points, at: x)
                let point = CGPoint(x: CGFloat(x) * size.width, y: (1 - CGFloat(y)) * size.height)
                if step == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }

    private func handleDrag(_ drag: DragGesture.Value, size: CGSize) {
        if !isEditing {
            isEditing = true
            onEditingChanged(true)
            let start = normalized(drag.startLocation, in: size)
            let nearest = points.enumerated().min { a, b in
                hypot(a.element.x - start.x, a.element.y - start.y) < hypot(b.element.x - start.x, b.element.y - start.y)
            }
            if let nearest, hypot(nearest.element.x - start.x, nearest.element.y - start.y) < 0.08 {
                dragIndex = nearest.offset
            } else {
                let x = min(max(start.x, 0.01), 0.99)
                let newPoint = CurvePoint(x: x, y: ToneCurveMath.evaluate(points, at: x))
                var updated = points
                let insertAt = updated.firstIndex { $0.x > x } ?? updated.count
                updated.insert(newPoint, at: insertAt)
                points = updated
                dragIndex = insertAt
            }
        }
        guard let index = dragIndex, index < points.count else { return }
        let location = normalized(drag.location, in: size)
        let isEndpoint = index == 0 || index == points.count - 1

        // Dragging an inner point far outside the box removes it.
        if !isEndpoint && (location.y < -0.18 || location.y > 1.18 || location.x < -0.18 || location.x > 1.18) {
            var updated = points
            updated.remove(at: index)
            points = updated
            dragIndex = nil
            return
        }

        let lower = index > 0 ? points[index - 1].x + 0.01 : 0
        let upper = index < points.count - 1 ? points[index + 1].x - 0.01 : 1
        var updated = points
        updated[index] = CurvePoint(
            x: min(max(location.x, lower), max(upper, lower)),
            y: min(max(location.y, 0), 1)
        )
        points = updated
    }
}
