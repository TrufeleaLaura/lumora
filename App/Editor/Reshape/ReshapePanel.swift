import LumoraCore
import SwiftUI

extension EditorSession {
    func paintLiquify(_ phase: PaintPhase, at point: CGPoint) {
        let p = SIMD2(Double(point.x), Double(point.y))
        brushCursor = point
        switch phase {
        case .began:
            beginChange()
            document.liquify.append(LiquifyStroke(tool: liquifyTool, points: [p], radius: liquifySize, strength: liquifyStrength))
        case .moved, .ended:
            guard let index = document.liquify.indices.last, let last = document.liquify[index].points.last else { return }
            let extent = proxy.extent
            let aspect = Double(extent.height / max(extent.width, 1))
            let dx = p.x - last.x
            let dy = (p.y - last.y) * aspect
            // Push follows the finger closely; the others only need a coarse path.
            let spacing = liquifyTool == .push ? liquifySize * 0.12 : liquifySize * 0.3
            if (dx * dx + dy * dy).squareRoot() >= spacing {
                document.liquify[index].points.append(p)
            }
            if phase == .ended {
                endChange(label: liquifyTool.title)
            }
        }
    }

    func undoLastLiquify() {
        guard !document.liquify.isEmpty else { return }
        perform("Remove last stroke") { $0.liquify.removeLast() }
    }

    func clearLiquify() {
        perform("Reset reshape") { $0.liquify = [] }
    }
}

/// Manual reshaping: push, enlarge, shrink and restore brushes.
struct ReshapePanel: View {
    @ObservedObject var session: EditorSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Brush", selection: $session.liquifyTool) {
                ForEach(LiquifyTool.allCases) { tool in
                    Text(tool.title).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(Darkroom.stone)
                        .fixedSize(horizontal: false, vertical: true)
                    ToolSlider(title: "Size", value: $session.liquifySize, range: 0.02...0.3, format: { "\(Int(($0 * 100).rounded()))%" })
                    ToolSlider(title: "Strength", value: $session.liquifyStrength, range: 5...100, format: { "\(Int($0.rounded()))" })
                    HStack {
                        Toggle(isOn: $session.liquifyPaints) {
                            Label(session.liquifyPaints ? "Brush" : "Move", systemImage: session.liquifyPaints ? "hand.draw" : "hand.raised")
                                .font(.footnote)
                        }
                        .toggleStyle(.button)
                        Spacer()
                        Button {
                            session.undoLastLiquify()
                        } label: {
                            Label("Last", systemImage: "arrow.uturn.backward")
                                .font(.footnote)
                        }
                        .disabled(session.document.liquify.isEmpty)
                        Button(role: .destructive) {
                            session.clearLiquify()
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                                .font(.footnote)
                        }
                        .disabled(session.document.liquify.isEmpty)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var hint: String {
        switch session.liquifyTool {
        case .push: return "Drag to nudge an outline: slim a waist, shape a jaw, fix a strand of hair. Small, gentle strokes look most natural."
        case .bloat: return "Tap or rub to enlarge (eyes, lips, curves)."
        case .pinch: return "Tap or rub to shrink (nose, a bulge in clothing)."
        case .restore: return "Brush over an area to bring it back to the original."
        }
    }
}

/// The brush circle while reshaping.
struct ReshapeCanvasOverlay: View {
    @ObservedObject var renderer: CanvasRenderer
    @ObservedObject var session: EditorSession

    var body: some View {
        let frame = renderer.imageFrame
        ZStack(alignment: .topLeading) {
            if let cursor = session.brushCursor, frame.width > 0 {
                let radius = CGFloat(session.liquifySize) * frame.width
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                    .frame(width: radius * 2, height: radius * 2)
                    .shadow(color: .black.opacity(0.5), radius: 1)
                    .position(x: frame.minX + cursor.x * frame.width, y: frame.minY + (1 - cursor.y) * frame.height)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
