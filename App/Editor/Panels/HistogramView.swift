import CoreImage
import LumoraCore
import LumoraEngine
import SwiftUI

extension EditorSession {
    /// Recomputes the histogram shortly after the preview stops changing.
    func scheduleHistogram(_ preview: CIImage) {
        histogramTask?.cancel()
        histogramTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            let data = await Task.detached(priority: .utility) { Histogram.compute(preview) }.value
            guard !Task.isCancelled else { return }
            self?.histogram = data
        }
    }

    /// White-balance eyedropper: makes the tapped spot neutral grey.
    func pickWhiteBalance(at point: CGPoint) {
        let extent = proxy.extent
        let size = max(3, extent.width * 0.008)
        let rect = CGRect(
            x: extent.minX + point.x * extent.width - size / 2,
            y: extent.minY + point.y * extent.height - size / 2,
            width: size,
            height: size
        ).intersection(extent)
        guard !rect.isEmpty else { return }
        let average = ImageStats.averageColor(of: proxy.cropped(to: rect))
        let color = SIMD3(Double(average.x), Double(average.y), Double(average.z))
        let pipeline = self.pipeline
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                pipeline.neutralizingWhiteBalance(for: color)
            }.value
            perform("White balance picker") { document in
                document.color.temperature = result.temperature
                document.color.tint = result.tint
            }
            pickingWhiteBalance = false
        }
    }
}

/// Luminance and RGB histogram; tap to show clipped areas on the photo.
struct HistogramView: View {
    @ObservedObject var session: EditorSession

    var body: some View {
        if let data = session.histogram {
            ZStack(alignment: .bottomLeading) {
                Canvas { context, size in
                    func path(_ values: [Float]) -> Path {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: size.height))
                            for (index, value) in values.enumerated() {
                                let x = size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                                path.addLine(to: CGPoint(x: x, y: size.height * (1 - CGFloat(value))))
                            }
                            path.addLine(to: CGPoint(x: size.width, y: size.height))
                            path.closeSubpath()
                        }
                    }
                    context.fill(path(data.luma), with: .color(.white.opacity(0.28)))
                    context.blendMode = .plusLighter
                    context.fill(path(data.red), with: .color(.red.opacity(0.35)))
                    context.fill(path(data.green), with: .color(.green.opacity(0.35)))
                    context.fill(path(data.blue), with: .color(.blue.opacity(0.4)))
                }
                HStack {
                    Circle()
                        .fill(data.shadowClip > 0.002 ? Color.blue : Color.white.opacity(0.25))
                        .frame(width: 6, height: 6)
                    Spacer()
                    Circle()
                        .fill(data.highlightClip > 0.002 ? Color.red : Color.white.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
                .padding(3)
            }
            .frame(width: 128, height: 54)
            .padding(6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(session.showsClipping ? AnyShapeStyle(Aura.diagonal) : AnyShapeStyle(Color.clear), lineWidth: 1.5)
            )
            .onTapGesture { session.showsClipping.toggle() }
            .accessibilityLabel(session.showsClipping ? "Histogram, clipping shown" : "Histogram")
            .accessibilityHint("Shows clipped highlights and shadows on the photo")
        }
    }
}
