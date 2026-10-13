import CoreImage
import Foundation

/// Segmentation mattes some iPhone photos carry (Portrait mode and many people shots):
/// hair, skin, teeth and sky, each far more precise than anything computed afterwards.
/// Images are upright and cover the whole photo; nil when the photo has no such matte.
public struct SemanticMattes: @unchecked Sendable {
    public var hair: CIImage?
    public var skin: CIImage?
    public var teeth: CIImage?
    public var sky: CIImage?

    public init(hair: CIImage? = nil, skin: CIImage? = nil, teeth: CIImage? = nil, sky: CIImage? = nil) {
        self.hair = hair
        self.skin = skin
        self.teeth = teeth
        self.sky = sky
    }

    public var isEmpty: Bool { hair == nil && skin == nil && teeth == nil && sky == nil }

    /// Reads the mattes embedded in a photo file (HEIC/JPEG from the iPhone camera).
    public static func load(from data: Data) -> SemanticMattes {
        func matte(_ option: CIImageOption) -> CIImage? {
            guard let image = CIImage(data: data, options: [option: true, .applyOrientationProperty: true]),
                  !image.extent.isInfinite, image.extent.width > 0 else { return nil }
            return ImageSource.normalized(image)
        }
        return SemanticMattes(
            hair: matte(.auxiliarySemanticSegmentationHairMatte),
            skin: matte(.auxiliarySemanticSegmentationSkinMatte),
            teeth: matte(.auxiliarySemanticSegmentationTeethMatte),
            sky: matte(.auxiliarySemanticSegmentationSkyMatte)
        )
    }
}
