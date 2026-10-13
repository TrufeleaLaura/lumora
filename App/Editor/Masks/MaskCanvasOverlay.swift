import LumoraCore
import SwiftUI

/// On-canvas handles for the selected mask part: gradient lines, radial ellipse, control point,
/// brush cursor and picked points. Only the handles take touches; painting and taps go
/// through the canvas itself.
struct MaskCanvasOverlay: View {
    @ObservedObject var renderer: CanvasRenderer
    @ObservedObject var session: EditorSession

    /// Component state when a drag started (handles move relative to it).
    @State private var dragOrigin: MaskComponent?

    var body: some View {
        let frame = renderer.imageFrame
        ZStack(alignment: .topLeading) {
            if session.maskPanel == .mask, let component = session.selectedComponent, frame.width > 0 {
                switch component.kind {
                case .linear:
                    linear(component, frame: frame)
                case .radial:
                    radial(component, frame: frame)
                case .point:
                    controlPoint(component, frame: frame)
                case .brush:
                    if let cursor = session.brushCursor {
                        let center = viewPoint(SIMD2(Double(cursor.x), Double(cursor.y)), frame)
                        let radius = CGFloat(session.brush.size) * frame.width
                        Circle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                            .frame(width: radius * 2, height: radius * 2)
                            .overlay(Circle().stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).padding(radius * CGFloat(session.brush.feather / 100)))
                            .position(center)
                            .allowsHitTesting(false)
                    }
                case .color, .object:
                    ForEach(Array(component.points.enumerated()), id: \.offset) { _, point in
                        marker(viewPoint(point, frame), symbol: component.kind == .color ? "eyedropper" : "hand.tap")
                    }
                case .people:
                    if let person = component.person {
                        marker(viewPoint(person, frame), symbol: "person.fill")
                    }
                default:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "maskCanvas")
    }

    // MARK: - Geometry

    private func viewPoint(_ p: SIMD2<Double>, _ frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + CGFloat(p.x) * frame.width, y: frame.minY + CGFloat(1 - p.y) * frame.height)
    }

    private func normalized(_ point: CGPoint, _ frame: CGRect) -> SIMD2<Double> {
        SIMD2(Double((point.x - frame.minX) / frame.width), Double(1 - (point.y - frame.minY) / frame.height))
    }

    /// Normalized offset for a translation in view points.
    private func offset(_ translation: CGSize, _ frame: CGRect) -> SIMD2<Double> {
        SIMD2(Double(translation.width / frame.width), Double(-translation.height / frame.height))
    }

    private func marker(_ point: CGPoint, symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 22, height: 22)
            .background(Color.white, in: Circle())
            .shadow(radius: 2)
            .position(point)
            .allowsHitTesting(false)
    }

    private func handle(filled: Bool = true, size: CGFloat = 22) -> some View {
        Circle()
            .fill(filled ? Color.white : Color.black.opacity(0.35))
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.4), radius: 2)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }

    /// A drag that edits the component live and records one undo step at the end.
    private func handleDrag(_ label: String, onEnded: (() -> Void)? = nil, _ change: @escaping (MaskComponent, DragGesture.Value) -> MaskComponent) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("maskCanvas"))
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = session.selectedComponent
                    session.beginChange()
                }
                guard let origin = dragOrigin else { return }
                let updated = change(origin, value)
                session.dragComponent { $0 = updated }
            }
            .onEnded { _ in
                onEnded?()
                dragOrigin = nil
                session.endChange(label: label)
            }
    }

    // MARK: - Linear

    private func linear(_ c: MaskComponent, frame: CGRect) -> some View {
        let start = viewPoint(c.start, frame)
        let end = viewPoint(c.end, frame)
        let dx = end.x - start.x, dy = end.y - start.y
        let length = max(hypot(dx, dy), 1)
        // Lines run perpendicular to the start → end direction.
        let normal = CGPoint(x: -dy / length, y: dx / length)
        let reach = max(frame.width, frame.height) * 2
        func line(through p: CGPoint) -> Path {
            Path { path in
                path.move(to: CGPoint(x: p.x - normal.x * reach, y: p.y - normal.y * reach))
                path.addLine(to: CGPoint(x: p.x + normal.x * reach, y: p.y + normal.y * reach))
            }
        }
        let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        return ZStack {
            line(through: start).stroke(Color.white, lineWidth: 1.5)
            line(through: middle).stroke(Color.white.opacity(0.5), lineWidth: 1)
            line(through: end).stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
        .shadow(color: .black.opacity(0.5), radius: 1)
        .allowsHitTesting(false)
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                handle()
                    .position(start)
                    .gesture(handleDrag("Move gradient start") { origin, value in
                        var updated = origin
                        updated.start = origin.start + offset(value.translation, frame)
                        return updated
                    })
                handle(filled: false)
                    .position(end)
                    .gesture(handleDrag("Move gradient end") { origin, value in
                        var updated = origin
                        updated.end = origin.end + offset(value.translation, frame)
                        return updated
                    })
                handle(filled: false, size: 16)
                    .position(middle)
                    .gesture(handleDrag("Move gradient") { origin, value in
                        var updated = origin
                        let delta = offset(value.translation, frame)
                        updated.start = origin.start + delta
                        updated.end = origin.end + delta
                        return updated
                    })
            }
        }
    }

    // MARK: - Radial

    private func radial(_ c: MaskComponent, frame: CGRect) -> some View {
        let center = viewPoint(c.start, frame)
        let rx = CGFloat(c.radius.x) * frame.width
        let ry = CGFloat(c.radius.y) * frame.width
        let radians = CGFloat(c.angle) * .pi / 180
        // Axes in view space (y down): local x = (cos, -sin), local y = (-sin, -cos).
        let axisX = CGPoint(x: cos(radians), y: -sin(radians))
        let axisY = CGPoint(x: -sin(radians), y: -cos(radians))
        let edgeX = CGPoint(x: center.x + axisX.x * rx, y: center.y + axisX.y * rx)
        let edgeY = CGPoint(x: center.x + axisY.x * ry, y: center.y + axisY.y * ry)
        let inner = CGFloat(max(0.02, 1 - c.feather / 100))
        return ZStack(alignment: .topLeading) {
            Ellipse()
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: rx * 2, height: ry * 2)
                .rotationEffect(.radians(-Double(radians)))
                .position(center)
                .allowsHitTesting(false)
            Ellipse()
                .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: rx * 2 * inner, height: ry * 2 * inner)
                .rotationEffect(.radians(-Double(radians)))
                .position(center)
                .allowsHitTesting(false)
            handle()
                .position(center)
                .gesture(handleDrag("Move radial") { origin, value in
                    var updated = origin
                    updated.start = origin.start + offset(value.translation, frame)
                    return updated
                })
            handle(filled: false, size: 16)
                .position(edgeX)
                .gesture(handleDrag("Resize radial") { origin, value in
                    var updated = origin
                    let dx: CGFloat = value.location.x - center.x
                    let dy: CGFloat = value.location.y - center.y
                    let along: CGFloat = dx * axisX.x + dy * axisX.y
                    updated.radius.x = max(0.01, Double(along / frame.width))
                    return updated
                })
            handle(filled: false, size: 16)
                .position(edgeY)
                .gesture(handleDrag("Resize radial") { origin, value in
                    var updated = origin
                    let dx: CGFloat = value.location.x - center.x
                    let dy: CGFloat = value.location.y - center.y
                    let along: CGFloat = dx * axisY.x + dy * axisY.y
                    updated.radius.y = max(0.01, Double(along / frame.width))
                    return updated
                })
        }
        .shadow(color: .black.opacity(0.4), radius: 1)
    }

    // MARK: - Control point

    private func controlPoint(_ c: MaskComponent, frame: CGRect) -> some View {
        let center = viewPoint(c.start, frame)
        let radius = CGFloat(c.radius.x) * frame.width
        return ZStack(alignment: .topLeading) {
            Circle()
                .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                .frame(width: radius * 2, height: radius * 2)
                .position(center)
                .allowsHitTesting(false)
            handle()
                .position(center)
                .gesture(handleDrag("Move control point", onEnded: { session.resampleControlPoint() }) { origin, value in
                    var updated = origin
                    updated.start = origin.start + offset(value.translation, frame)
                    return updated
                })
        }
        .shadow(color: .black.opacity(0.4), radius: 1)
    }
}
