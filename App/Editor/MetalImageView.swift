import CoreImage
import LumoraEngine
import MetalKit
import SwiftUI

/// GPU canvas that draws a Core Image image aspect-fitted, in wide color.
struct MetalImageView: UIViewRepresentable {
    var image: CIImage?

    func makeCoordinator() -> Renderer {
        Renderer()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: RenderContext.device)
        view.framebufferOnly = false
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = true
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.backgroundColor = .black
        if let layer = view.layer as? CAMetalLayer {
            layer.colorspace = RenderContext.displayP3
        }
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.image = image
        view.setNeedsDisplay()
    }

    final class Renderer: NSObject, MTKViewDelegate {
        var image: CIImage?
        private let commandQueue: MTLCommandQueue? = RenderContext.device?.makeCommandQueue()

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            view.setNeedsDisplay()
        }

        func draw(in view: MTKView) {
            let size = view.drawableSize
            guard size.width > 0, size.height > 0,
                  let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue?.makeCommandBuffer() else { return }

            let bounds = CGRect(origin: .zero, size: size)
            var output = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: bounds)

            if let image {
                let extent = image.extent
                if extent.width > 0, extent.height > 0, !extent.isInfinite {
                    let scale = min(size.width / extent.width, size.height / extent.height)
                    let offsetX = (size.width - extent.width * scale) / 2
                    let offsetY = (size.height - extent.height * scale) / 2
                    let transform = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
                        .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                        .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
                    output = image.transformed(by: transform).composited(over: output)
                }
            }

            RenderContext.shared.render(
                output,
                to: drawable.texture,
                commandBuffer: commandBuffer,
                bounds: bounds,
                colorSpace: RenderContext.displayP3
            )
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
