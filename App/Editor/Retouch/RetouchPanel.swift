import LumoraCore
import SwiftUI

/// Heal, clone and remove, plus red-eye.
struct RetouchPanel: View {
    @ObservedObject var session: EditorSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Tool", selection: $session.retouchTool) {
                    ForEach(RetouchTool.allCases) { tool in
                        Label(tool.title, systemImage: tool.symbol).tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                if session.isRetouching {
                    ProgressView()
                        .padding(.leading, 6)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if session.retouchTool == .remove {
                        Toggle("Tap objects or people", isOn: $session.removeByTapping)
                            .tint(Theme.accent)
                    }
                    if session.retouchTool == .clone {
                        HStack {
                            Label(session.cloneSource == nil ? "Step 1: tap what to copy" : "Step 2: paint where to copy it",
                                  systemImage: session.cloneSource == nil ? "scope" : "paintbrush.pointed")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                            Spacer()
                            if session.cloneSource != nil {
                                Button("New source") { session.cloneSource = nil }
                                    .font(.footnote)
                            }
                        }
                    }
                    if !(session.retouchTool == .remove && session.removeByTapping) {
                        ToolSlider(title: "Brush size", value: $session.retouchSize, range: 0.005...0.15, format: { "\(Int(($0 * 100).rounded()))%" })
                    }
                    SliderList(session: session, specs: [
                        SliderSpec(id: "retouch.redEye", title: "Red eye", range: 0...100, style: .integer, keyPath: \EditDocument.retouch.redEye),
                    ])
                    HStack {
                        Text(countText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            session.undoLastRetouch()
                        } label: {
                            Label("Last", systemImage: "arrow.uturn.backward")
                                .font(.footnote)
                        }
                        .disabled(session.document.retouch.operations.isEmpty)
                        Button(role: .destructive) {
                            session.clearRetouching()
                        } label: {
                            Label("Clear", systemImage: "trash")
                                .font(.footnote)
                        }
                        .disabled(session.document.retouch.operations.isEmpty)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var hint: String {
        switch session.retouchTool {
        case .heal:
            return "Tap a spot or paint over blemishes, dust or small objects. They're filled with matching texture from nearby."
        case .clone:
            return "Copies one part of the photo over another: pick the source, then paint. The crosshair shows what's being copied. You can drag the source circle afterwards."
        case .remove:
            return session.removeByTapping
                ? "Tap an object or person to remove it. The background is rebuilt from its surroundings."
                : "Paint over anything you want gone. Cover it completely, including its shadow."
        }
    }

    private var countText: String {
        let count = session.document.retouch.operations.count
        return count == 1 ? "1 fix" : "\(count) fixes"
    }
}

/// The stroke being painted, and the clone source handle.
struct RetouchCanvasOverlay: View {
    @ObservedObject var renderer: CanvasRenderer
    @ObservedObject var session: EditorSession
    @State private var dragOffset: SIMD2<Double>?

    var body: some View {
        let frame = renderer.imageFrame
        ZStack(alignment: .topLeading) {
            if frame.width > 0 {
                if let stroke = session.pendingRetouch {
                    strokePath(stroke, frame: frame)
                        .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: CGFloat(stroke.radius) * frame.width * 2, lineCap: .round, lineJoin: .round))
                        .allowsHitTesting(false)
                    // Clone: the crosshair follows the brush on the source area.
                    if let offset = session.cloneStrokeOffset, let last = stroke.points.last {
                        crosshair(viewPoint(last + offset, frame), radius: CGFloat(stroke.radius) * frame.width)
                    }
                } else if session.retouchTool == .clone, let source = session.cloneSource {
                    crosshair(viewPoint(source, frame), radius: CGFloat(session.retouchSize) * frame.width)
                }
                if !session.isRetouching, let index = session.selectedRetouchIndex {
                    let operation = session.document.retouch.operations[index]
                    if operation.tool == .clone, let center = center(of: operation) {
                        cloneHandles(operation, center: center, frame: frame)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "retouchCanvas")
    }

    private func viewPoint(_ p: SIMD2<Double>, _ frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + CGFloat(p.x) * frame.width, y: frame.minY + CGFloat(1 - p.y) * frame.height)
    }

    private func crosshair(_ point: CGPoint, radius: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: max(radius * 2, 24), height: max(radius * 2, 24))
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.6), radius: 1.5)
        .position(point)
        .allowsHitTesting(false)
    }

    private func strokePath(_ stroke: BrushStroke, frame: CGRect) -> Path {
        Path { path in
            guard let first = stroke.points.first else { return }
            path.move(to: viewPoint(first, frame))
            if stroke.points.count == 1 {
                path.addLine(to: viewPoint(first, frame))
            }
            for point in stroke.points.dropFirst() {
                path.addLine(to: viewPoint(point, frame))
            }
        }
    }

    private func center(of operation: RetouchOperation) -> SIMD2<Double>? {
        let points = operation.strokes.flatMap(\.points)
        guard !points.isEmpty else { return nil }
        return points.reduce(SIMD2<Double>(0, 0), +) / Double(points.count)
    }

    private func cloneHandles(_ operation: RetouchOperation, center: SIMD2<Double>, frame: CGRect) -> some View {
        let offset = dragOffset ?? operation.sourceOffset
        let target = viewPoint(center, frame)
        let source = viewPoint(center + offset, frame)
        let radius = CGFloat(operation.strokes.first?.radius ?? 0.03) * frame.width
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: target)
                path.addLine(to: source)
            }
            .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .allowsHitTesting(false)
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .frame(width: max(radius * 2, 30), height: max(radius * 2, 30))
                .overlay(Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").font(.caption).foregroundStyle(.white))
                .shadow(color: .black.opacity(0.4), radius: 2)
                .contentShape(Circle())
                .position(source)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("retouchCanvas"))
                        .onChanged { value in
                            let start = operation.sourceOffset
                            let dx = Double(value.translation.width / frame.width)
                            let dy = Double(-value.translation.height / frame.height)
                            dragOffset = SIMD2(start.x + dx, start.y + dy)
                        }
                        .onEnded { _ in
                            if let offset = dragOffset {
                                session.moveCloneSource(operation.id, offset: offset)
                            }
                            dragOffset = nil
                        }
                )
        }
    }
}
