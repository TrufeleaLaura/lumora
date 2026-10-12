import CoreImage
import LumoraEngine
import MetalKit
import UIKit

enum CompareMode: Equatable {
    case none
    /// Press-and-hold: show the unedited photo.
    case holding
    /// Before/after split with a draggable divider.
    case split
}

/// Draws the editor canvas: zoom/pan, before/after compare, and sharp full-resolution
/// refinement of the visible area when zoomed in beyond the preview proxy's resolution.
///
/// Coordinates: "image space" is the preview proxy's pixel grid (Core Image, y up);
/// "view space" is the drawable's pixel grid (also y up, origin bottom-left).
@MainActor
final class CanvasRenderer: NSObject, MTKViewDelegate, UIGestureRecognizerDelegate {
    // MARK: Inputs

    /// Edited preview proxy.
    var previewImage: CIImage? {
        didSet { contentChanged() }
    }
    /// Unedited preview proxy (compare).
    var originalImage: CIImage? {
        didSet { requestDraw() }
    }
    var compareMode: CompareMode = .none {
        didSet { if compareMode != oldValue { requestDraw() } }
    }
    /// 0...1 horizontal position of the split divider.
    var splitPosition: CGFloat = 0.5 {
        didSet { requestDraw() }
    }
    /// Full-resolution edited image (lazy Core Image graph) and its size, for zoomed-in refinement.
    var fullResolutionImage: (() -> CIImage?)?
    var fullResolutionSize: CGSize = .zero

    /// Called with true/false when the user presses and holds the photo.
    var onHoldChanged: ((Bool) -> Void)?

    // MARK: State

    private weak var view: MTKView?
    private let commandQueue: MTLCommandQueue? = RenderContext.device?.makeCommandQueue()
    /// 1 = whole photo fits the view.
    private(set) var zoom: CGFloat = 1
    /// Offset of the photo center from the view center, in view pixels.
    private var pan: CGPoint = .zero
    private var generation = 0
    private var refined: (image: CIImage, generation: Int)?
    private var refineDebounce: Task<Void, Never>?
    private var refineTask: Task<Void, Never>?

    // MARK: View setup

    func makeView() -> MTKView {
        let view = MTKView(frame: .zero, device: RenderContext.device)
        view.framebufferOnly = false
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = true
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.backgroundColor = .black
        view.isMultipleTouchEnabled = true
        if let layer = view.layer as? CAMetalLayer {
            layer.colorspace = RenderContext.displayP3
        }
        view.delegate = self

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        view.addGestureRecognizer(pan)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
        hold.minimumPressDuration = 0.25
        hold.delegate = self
        view.addGestureRecognizer(hold)

        self.view = view
        return view
    }

    func requestDraw() {
        view?.setNeedsDisplay()
    }

    func resetZoom() {
        zoom = 1
        pan = .zero
        viewTransformChanged()
    }

    // MARK: Geometry

    private var drawableSize: CGSize { view?.drawableSize ?? .zero }

    private var pixelsPerPoint: CGFloat {
        guard let view, view.bounds.width > 0 else { return 3 }
        return view.drawableSize.width / view.bounds.width
    }

    private var imageExtent: CGRect { previewImage?.extent ?? originalImage?.extent ?? .zero }

    private var fitScale: CGFloat {
        let size = drawableSize
        let extent = imageExtent
        guard extent.width > 0, extent.height > 0, size.width > 0, size.height > 0 else { return 1 }
        return min(size.width / extent.width, size.height / extent.height)
    }

    /// View pixels per preview pixel.
    private var displayScale: CGFloat { fitScale * zoom }

    private var maxZoom: CGFloat {
        let extent = imageExtent
        guard extent.width > 0, fullResolutionSize.width > 0 else { return 6 }
        // Allow up to 2 screen pixels per original pixel.
        let oneToOne = (fullResolutionSize.width / extent.width) / fitScale
        return max(4, oneToOne * 2)
    }

    /// Maps image space to view space.
    private var displayTransform: CGAffineTransform {
        let extent = imageExtent
        let size = drawableSize
        let s = displayScale
        return CGAffineTransform(translationX: -extent.midX, y: -extent.midY)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: size.width / 2 + pan.x, y: size.height / 2 + pan.y))
    }

    /// Converts a UIKit point (y down, points) to view space (y up, pixels).
    private func viewPoint(_ point: CGPoint) -> CGPoint {
        let ppp = pixelsPerPoint
        return CGPoint(x: point.x * ppp, y: drawableSize.height - point.y * ppp)
    }

    private func clampPan() {
        let extent = imageExtent
        let size = drawableSize
        let s = displayScale
        let maxX = max(0, (extent.width * s - size.width) / 2)
        let maxY = max(0, (extent.height * s - size.height) / 2)
        pan.x = min(max(pan.x, -maxX), maxX)
        pan.y = min(max(pan.y, -maxY), maxY)
    }

    /// Changes the zoom keeping the image point under `anchor` (view space) fixed.
    private func setZoom(_ newZoom: CGFloat, anchor: CGPoint) {
        let oldScale = displayScale
        zoom = min(max(newZoom, 1), maxZoom)
        let newScale = displayScale
        let size = drawableSize
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        pan.x = anchor.x - center.x - (anchor.x - center.x - pan.x) * newScale / oldScale
        pan.y = anchor.y - center.y - (anchor.y - center.y - pan.y) * newScale / oldScale
        clampPan()
        viewTransformChanged()
    }

    // MARK: Gestures

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Pinch and pan work together; holding (compare) stays exclusive.
        !(gestureRecognizer is UILongPressGestureRecognizer || other is UILongPressGestureRecognizer)
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            let anchor = viewPoint(recognizer.location(in: recognizer.view))
            setZoom(zoom * recognizer.scale, anchor: anchor)
            recognizer.scale = 1
        case .ended, .cancelled:
            settle()
        default:
            break
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard zoom > 1.001 else { return }
        switch recognizer.state {
        case .began, .changed:
            let translation = recognizer.translation(in: recognizer.view)
            let ppp = pixelsPerPoint
            pan.x += translation.x * ppp
            pan.y -= translation.y * ppp
            recognizer.setTranslation(.zero, in: recognizer.view)
            clampPan()
            viewTransformChanged()
        case .ended, .cancelled:
            settle()
        default:
            break
        }
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if zoom > 1.01 {
            resetZoom()
        } else {
            setZoom(min(3, maxZoom), anchor: viewPoint(recognizer.location(in: recognizer.view)))
        }
        settle()
    }

    @objc private func handleHold(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            onHoldChanged?(true)
        case .ended, .cancelled, .failed:
            onHoldChanged?(false)
        default:
            break
        }
    }

    // MARK: Refinement

    private func contentChanged() {
        generation += 1
        requestDraw()
        scheduleRefine(delay: 0.25)
    }

    private func viewTransformChanged() {
        generation += 1
        requestDraw()
    }

    private func settle() {
        scheduleRefine(delay: 0.12)
    }

    /// When zoomed in past the proxy's resolution, renders the visible area from the
    /// full-resolution image in the background and overlays it once ready.
    private func scheduleRefine(delay: TimeInterval) {
        refineDebounce?.cancel()
        guard displayScale > 1.05, fullResolutionSize.width > 0, fullResolutionImage != nil else { return }
        refineDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.startRefine()
        }
    }

    private func startRefine() {
        let extent = imageExtent
        guard extent.width > 0, let full = fullResolutionImage?() else { return }
        let token = generation
        let k = extent.width / fullResolutionSize.width
        // Original space -> image space -> view space.
        let transform = CGAffineTransform(scaleX: k, y: k).concatenating(displayTransform)
        let viewRect = CGRect(origin: .zero, size: drawableSize)
        let placed = full.transformed(by: transform)
        let visible = placed.extent.intersection(viewRect).integral
        guard !visible.isEmpty, !visible.isInfinite else { return }

        refineTask?.cancel()
        refineTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let cgImage = RenderContext.shared.createCGImage(placed, from: visible, format: .RGBA8, colorSpace: RenderContext.displayP3) else { return }
            let image = CIImage(cgImage: cgImage).transformed(by: CGAffineTransform(translationX: visible.minX, y: visible.minY))
            await self?.applyRefined(image, token: token)
        }
    }

    private func applyRefined(_ image: CIImage, token: Int) {
        guard generation == token else { return }
        refined = (image, token)
        requestDraw()
    }

    // MARK: MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        MainActor.assumeIsolated {
            self.clampPan()
            self.generation += 1
            view.setNeedsDisplay()
        }
    }

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            self.render(in: view)
        }
    }

    private func render(in view: MTKView) {
        let size = view.drawableSize
        guard size.width > 0, size.height > 0,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer() else { return }

        let bounds = CGRect(origin: .zero, size: size)
        let transform = displayTransform
        var output = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: bounds)

        if compareMode == .holding, let original = originalImage {
            output = original.transformed(by: transform).composited(over: output)
        } else if let preview = previewImage {
            output = preview.transformed(by: transform).composited(over: output)
            if let refined, refined.generation == generation {
                output = refined.image.composited(over: output)
            }
            if compareMode == .split, let original = originalImage {
                let splitX = (size.width * splitPosition).rounded()
                let left = original.transformed(by: transform).cropped(to: CGRect(x: 0, y: 0, width: splitX, height: size.height))
                output = left.composited(over: output)
            }
        }

        RenderContext.shared.render(
            output.cropped(to: bounds),
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: bounds,
            colorSpace: RenderContext.displayP3
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
