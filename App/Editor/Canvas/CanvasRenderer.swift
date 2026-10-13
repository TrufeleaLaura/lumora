import CoreImage
import LumoraEngine
import MetalKit
import UIKit

enum PaintPhase {
    case began, moved, ended
}

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
final class CanvasRenderer: NSObject, ObservableObject, MTKViewDelegate, UIGestureRecognizerDelegate {
    /// Where the photo is drawn, in view points (UIKit coordinates). Overlays (crop handles,
    /// face/body markers) use it to line up with the image.
    @Published private(set) var imageFrame: CGRect = .zero
    /// When false, pinch/pan/double-tap are ignored (e.g. while cropping).
    var allowsZoom = true {
        didSet { if !allowsZoom { resetZoom() } }
    }

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
    /// When set, one-finger drags paint (normalized image point, y up) and two fingers pan/zoom.
    var onPaint: ((PaintPhase, CGPoint) -> Void)? {
        didSet { configureInteraction() }
    }
    /// When set, single taps report the tapped normalized image point (y up).
    var onTap: ((CGPoint) -> Void)? {
        didSet { configureInteraction() }
    }

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
    private var panRecognizer: UIPanGestureRecognizer?
    private var paintRecognizer: UIPanGestureRecognizer?
    private var tapRecognizer: UITapGestureRecognizer?
    private var holdRecognizer: UILongPressGestureRecognizer?

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

        let paint = UIPanGestureRecognizer(target: self, action: #selector(handlePaint(_:)))
        paint.maximumNumberOfTouches = 1
        paint.delegate = self
        view.addGestureRecognizer(paint)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.require(toFail: doubleTap)
        view.addGestureRecognizer(tap)

        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "canvas"
        view.accessibilityLabel = "Photo"
        panRecognizer = pan
        paintRecognizer = paint
        tapRecognizer = tap
        holdRecognizer = hold
        self.view = view
        configureInteraction()
        return view
    }

    /// Paint mode: one finger paints, panning needs two fingers, hold-to-compare is off.
    private func configureInteraction() {
        let painting = onPaint != nil
        paintRecognizer?.isEnabled = painting
        panRecognizer?.minimumNumberOfTouches = painting ? 2 : 1
        holdRecognizer?.isEnabled = !painting
        tapRecognizer?.isEnabled = onTap != nil
    }

    /// Normalized image coordinates (0...1, y up) of a point in the view.
    private func normalizedPoint(_ location: CGPoint) -> CGPoint {
        let extent = imageExtent
        guard extent.width > 0, extent.height > 0 else { return .zero }
        let p = imagePoint(fromViewPoint: location)
        return CGPoint(x: (p.x - extent.minX) / extent.width, y: (p.y - extent.minY) / extent.height)
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
        guard allowsZoom else { return }
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
        guard allowsZoom, zoom > 1.001 else { return }
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
        guard allowsZoom else { return }
        if zoom > 1.01 {
            resetZoom()
        } else {
            setZoom(min(3, maxZoom), anchor: viewPoint(recognizer.location(in: recognizer.view)))
        }
        settle()
    }

    @objc private func handlePaint(_ recognizer: UIPanGestureRecognizer) {
        guard let onPaint else { return }
        let point = normalizedPoint(recognizer.location(in: recognizer.view))
        switch recognizer.state {
        case .began:
            onPaint(.began, point)
        case .changed:
            onPaint(.moved, point)
        case .ended, .cancelled, .failed:
            onPaint(.ended, point)
        default:
            break
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let onTap, recognizer.state == .ended else { return }
        onTap(normalizedPoint(recognizer.location(in: recognizer.view)))
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
        // Lets UI tests check what is on screen.
        let extent = imageExtent
        view?.accessibilityValue = "\(Int(extent.width))x\(Int(extent.height)) at \(Int(extent.minX)),\(Int(extent.minY)) zoom \(String(format: "%.2f", zoom))"

        clampPan()
        publishViewport()
        requestDraw()
        scheduleRefine(delay: 0.25)
    }

    private func viewTransformChanged() {
        generation += 1
        publishViewport()
        requestDraw()
    }

    private func publishViewport() {
        let ppp = pixelsPerPoint
        guard ppp > 0, drawableSize.height > 0 else { return }
        let rect = imageExtent.applying(displayTransform)
        let frame = CGRect(
            x: rect.minX / ppp,
            y: (drawableSize.height - rect.maxY) / ppp,
            width: rect.width / ppp,
            height: rect.height / ppp
        )
        if frame != imageFrame {
            imageFrame = frame
        }
    }

    /// Converts a point in view points (UIKit) to preview-image pixel coordinates (Core Image, y up).
    func imagePoint(fromViewPoint point: CGPoint) -> CGPoint {
        viewPoint(point).applying(displayTransform.inverted())
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
            self.publishViewport()
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
