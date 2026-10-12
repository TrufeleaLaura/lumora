import CoreImage
import LumoraCore
import LumoraEngine
import SwiftUI
import UIKit

/// Renders small previews of looks and presets on the current photo, in the background.
@MainActor
final class LookThumbnails: ObservableObject {
    @Published private(set) var images: [String: UIImage] = [:]

    private let base: CIImage
    private let analysis: ImageAnalysis
    private let scale: CGFloat
    private var pending: Set<String> = []

    init(proxy: CIImage, fullSize: CGSize) {
        let small = ImageSource.scaled(proxy, maxDimension: 180)
        let base = RenderContext.materialize(small, context: RenderContext.shared)
        self.base = base
        self.analysis = ImageAnalysis(image: base)
        self.scale = base.extent.width / max(fullSize.width, 1)
    }

    /// Returns the cached thumbnail, or starts rendering it and returns nil for now.
    func image(for key: String, document: EditDocument) -> UIImage? {
        if let image = images[key] {
            return image
        }
        guard !pending.contains(key) else { return nil }
        pending.insert(key)
        let base = self.base
        let analysis = self.analysis
        let scale = self.scale
        Task.detached(priority: .utility) { [weak self] in
            let rendered = RenderPipeline().apply(document, to: base, scale: scale, analysis: analysis)
            guard let cgImage = RenderContext.shared.createCGImage(rendered, from: rendered.extent, format: .RGBA8, colorSpace: RenderContext.displayP3) else { return }
            await self?.store(UIImage(cgImage: cgImage), for: key)
        }
        return nil
    }

    func invalidate(_ key: String) {
        images[key] = nil
        pending.remove(key)
    }

    private func store(_ image: UIImage, for key: String) {
        images[key] = image
        pending.remove(key)
    }
}
