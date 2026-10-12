import LumoraCore
import SwiftUI

/// Crop rectangle editor drawn over the canvas: dimmed outside area, rule-of-thirds grid,
/// draggable corners/edges (aspect-locked when a ratio is chosen) and drag-to-move.
struct CropOverlay: View {
    @ObservedObject var renderer: CanvasRenderer
    @ObservedObject var session: EditorSession

    @State private var dragStart: CropRect?
    @State private var handle: Handle?

    enum Handle {
        case topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right, move
    }

    var body: some View {
        GeometryReader { geometry in
            let frame = renderer.imageFrame
            let crop = session.document.geometry.crop
            let rect = viewRect(crop, in: frame)
            ZStack {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    path.addRect(rect)
                }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

                Path { path in
                    for i in 1...2 {
                        let x = rect.minX + rect.width * CGFloat(i) / 3
                        let y = rect.minY + rect.height * CGFloat(i) / 3
                        path.move(to: CGPoint(x: x, y: rect.minY))
                        path.addLine(to: CGPoint(x: x, y: rect.maxY))
                        path.move(to: CGPoint(x: rect.minX, y: y))
                        path.addLine(to: CGPoint(x: rect.maxX, y: y))
                    }
                }
                .stroke(Color.white.opacity(handle == nil ? 0.25 : 0.55), lineWidth: 0.5)

                Rectangle()
                    .path(in: rect)
                    .stroke(Color.white, lineWidth: 1)

                cornerHandles(rect)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { drag in
                        if dragStart == nil {
                            handle = hitTest(drag.startLocation, rect: rect)
                            guard handle != nil else { return }
                            dragStart = crop
                            session.beginChange()
                        }
                        guard let start = dragStart, let handle else { return }
                        update(start: start, handle: handle, translation: drag.translation, frame: frame)
                    }
                    .onEnded { _ in
                        if dragStart != nil {
                            session.endChange(label: "Crop")
                        }
                        dragStart = nil
                        handle = nil
                    }
            )
        }
    }

    // MARK: - Geometry

    private func viewRect(_ crop: CropRect, in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + CGFloat(crop.x) * frame.width,
            y: frame.minY + CGFloat(1 - crop.y - crop.height) * frame.height,
            width: CGFloat(crop.width) * frame.width,
            height: CGFloat(crop.height) * frame.height
        )
    }

    private func cornerHandles(_ rect: CGRect) -> Path {
        let length = min(22, rect.width / 3, rect.height / 3)
        return Path { path in
            for corner in [(rect.minX, rect.minY, 1.0, 1.0), (rect.maxX, rect.minY, -1.0, 1.0), (rect.minX, rect.maxY, 1.0, -1.0), (rect.maxX, rect.maxY, -1.0, -1.0)] {
                path.move(to: CGPoint(x: corner.0 + CGFloat(corner.2) * length, y: corner.1))
                path.addLine(to: CGPoint(x: corner.0, y: corner.1))
                path.addLine(to: CGPoint(x: corner.0, y: corner.1 + CGFloat(corner.3) * length))
            }
        }
    }

    private func hitTest(_ point: CGPoint, rect: CGRect) -> Handle? {
        let corner: CGFloat = 34
        let edge: CGFloat = 26
        func near(_ a: CGPoint) -> Bool { hypot(point.x - a.x, point.y - a.y) < corner }
        if near(CGPoint(x: rect.minX, y: rect.minY)) { return .topLeft }
        if near(CGPoint(x: rect.maxX, y: rect.minY)) { return .topRight }
        if near(CGPoint(x: rect.minX, y: rect.maxY)) { return .bottomLeft }
        if near(CGPoint(x: rect.maxX, y: rect.maxY)) { return .bottomRight }
        let insideX = point.x > rect.minX - edge && point.x < rect.maxX + edge
        let insideY = point.y > rect.minY - edge && point.y < rect.maxY + edge
        if insideX && abs(point.y - rect.minY) < edge { return .top }
        if insideX && abs(point.y - rect.maxY) < edge { return .bottom }
        if insideY && abs(point.x - rect.minX) < edge { return .left }
        if insideY && abs(point.x - rect.maxX) < edge { return .right }
        if rect.contains(point) { return .move }
        return nil
    }

    /// Applies a drag to the crop rectangle (normalized, y up).
    private func update(start: CropRect, handle: Handle, translation: CGSize, frame: CGRect) {
        guard frame.width > 0, frame.height > 0 else { return }
        let dx = Double(translation.width / frame.width)
        let dy = Double(-translation.height / frame.height)
        let minimum = 0.05

        var left = start.x
        var right = start.x + start.width
        var bottom = start.y
        var top = start.y + start.height

        switch handle {
        case .move:
            let x = min(max(start.x + dx, 0), 1 - start.width)
            let y = min(max(start.y + dy, 0), 1 - start.height)
            session.document.geometry.crop = CropRect(x: x, y: y, width: start.width, height: start.height)
            return
        case .topLeft: left += dx; top += dy
        case .topRight: right += dx; top += dy
        case .bottomLeft: left += dx; bottom += dy
        case .bottomRight: right += dx; bottom += dy
        case .top: top += dy
        case .bottom: bottom += dy
        case .left: left += dx
        case .right: right += dx
        }

        left = min(max(left, 0), right - minimum)
        right = max(min(right, 1), left + minimum)
        bottom = min(max(bottom, 0), top - minimum)
        top = max(min(top, 1), bottom + minimum)

        var rect = CropRect(x: left, y: bottom, width: right - left, height: top - bottom)

        // Keep the chosen aspect ratio, anchored on the opposite corner/edge.
        let size = renderer.imageFrame.size
        if let ratio = session.document.geometry.aspect.ratio(originalWidth: Double(size.width), originalHeight: Double(size.height)) {
            let normalizedRatio = ratio * Double(frame.height / frame.width)
            switch handle {
            case .top, .bottom:
                let width = rect.height * normalizedRatio
                let centerX = start.x + start.width / 2
                rect = CropRect(x: centerX - width / 2, y: rect.y, width: width, height: rect.height)
            case .left, .right:
                let height = rect.width / normalizedRatio
                let centerY = start.y + start.height / 2
                rect = CropRect(x: rect.x, y: centerY - height / 2, width: rect.width, height: height)
            default:
                var width = rect.width
                var height = width / normalizedRatio
                if height > rect.height + 1e-9 && handle != .move {
                    height = rect.height
                    width = height * normalizedRatio
                }
                let anchorRight = handle == .topLeft || handle == .bottomLeft
                let anchorTop = handle == .bottomLeft || handle == .bottomRight
                let x = anchorRight ? (start.x + start.width) - width : start.x
                let y = anchorTop ? (start.y + start.height) - height : start.y
                rect = CropRect(x: x, y: y, width: width, height: height)
            }
            // Shrink to fit inside the photo while keeping the ratio.
            if rect.x < 0 || rect.y < 0 || rect.x + rect.width > 1 || rect.y + rect.height > 1 {
                let fitted = GeometryMath.crop(aspect: ratio, imageWidth: Double(size.width), imageHeight: Double(size.height), around: rect.clamped(minimumSize: minimum))
                rect = fitted
            }
        }
        session.document.geometry.crop = rect.clamped(minimumSize: minimum)
    }
}
