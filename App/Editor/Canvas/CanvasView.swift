import MetalKit
import SwiftUI

/// SwiftUI host for the editor's `CanvasRenderer`. The renderer is owned by the editor
/// session so zoom state and gestures survive SwiftUI view updates.
struct CanvasView: UIViewRepresentable {
    let renderer: CanvasRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = renderer.makeView()
        // Never ask for more room than the layout offers (a large photo must not push the
        // top bar under the status bar).
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTKView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: proposal.height ?? 320)
    }
}
