import CoreImage
import Foundation
import LumoraCore

extension RenderPipeline {
    /// Body reshaping (waist, hips, butt, bust, thighs, arms, shoulders, head) and stretches
    /// (legs, height, neck), person by person.
    func applyBodyWarp(_ edits: BodyEditSettings, to input: CIImage, analysis: ImageAnalysis) -> CIImage {
        guard !edits.isIdentity else { return input }
        let extent = input.extent
        let aspect = Double(extent.height / max(extent.width, 1))
        var image = input
        for (index, body) in analysis.bodies.enumerated() {
            let settings = edits.settings(for: body.pose.anchor)
            if settings.hasReshape {
                let key = "body-\(index)-\(settings.hashValue)-\(Int(aspect * 10000))"
                if let field = analysis.cachedField(key: key, build: {
                    BodyReshape.field(for: body, settings: settings, aspect: aspect)
                }) {
                    image = applyDisplacement(field, to: image)
                }
            }
            if settings.hasStretch {
                let key = "stretch-\(index)-\(settings.legs)-\(settings.height)-\(settings.neck)"
                if let field = analysis.cachedField(key: key, build: {
                    BodyReshape.stretchField(for: body.pose, settings: settings)
                }) {
                    image = applyDisplacement(field, to: image)
                }
            }
        }
        return image
    }
}

extension RenderPipeline {
    /// Manual reshape strokes, as one warp over the whole photo.
    func applyLiquify(_ strokes: [LiquifyStroke], to image: CIImage, analysis: ImageAnalysis) -> CIImage {
        guard !strokes.isEmpty else { return image }
        let extent = image.extent
        let aspect = Double(extent.height / max(extent.width, 1))
        let key = "liquify-\(strokes.hashValue)-\(Int(aspect * 10000))"
        guard let field = analysis.cachedField(key: key, build: { LiquifyMath.field(strokes, aspect: aspect) }) else { return image }
        return applyDisplacement(field, to: image)
    }
}
