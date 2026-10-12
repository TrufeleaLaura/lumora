import MetalKit
import SwiftUI

/// SwiftUI host for the editor's `CanvasRenderer`. The renderer is owned by the editor
/// session so zoom state and gestures survive SwiftUI view updates.
struct CanvasView: UIViewRepresentable {
    let renderer: CanvasRenderer

    func makeUIView(context: Context) -> MTKView {
        renderer.makeView()
    }

    func updateUIView(_ view: MTKView, context: Context) {}
}
