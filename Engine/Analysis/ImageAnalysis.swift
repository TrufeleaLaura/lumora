import CoreImage
import Foundation
import LumoraCore

/// Results of the haze analysis used by Dehaze.
public struct HazeAnalysis {
    /// Low-resolution guided coefficients mapping perceptual luminance to transmission.
    public let coefficients: CIImage
    /// Atmospheric light color (linear RGB).
    public let airlight: SIMD3<Float>
}

/// Per-photo analysis computed once from the unedited preview and reused for every render
/// (preview, zoomed refinement and export). Everything is resolution-independent.
/// Properties compute lazily on first use and are thread-safe.
public final class ImageAnalysis: @unchecked Sendable {
    private let source: CIImage
    private let context: CIContext
    private let lock = NSLock()
    private var cachedToneBase: CIImage?
    private var cachedClarityBase: CIImage?
    private var cachedHaze: HazeAnalysis?
    private var cachedFaces: [FaceInfo]?
    private var cachedPerson: CIImage??
    private var cachedBodies: [BodyShape]?
    private let knownPoses: [BodyPose]?
    private var warpCache: [String: DisplacementField] = [:]
    private var cachedSubject: SubjectAnalysis??
    private let knownSubject: CIImage?
    private var cachedSky: CIImage??
    private var cachedSkyRegion: CGRectValue??
    private var cachedPivot: Float?
    private var cachedHair: CIImage??
    private var cachedHairRegion: CGRectValue??
    /// Mattes from the photo file (hair, skin, teeth, sky), stretched over the analyzed extent.
    public let mattes: SemanticMattes
    private var cachedBlemishes: [Int: [BlemishDetector.Spot]] = [:]

    private let knownLandmarks: [FaceLandmarks]?

    /// - Parameters:
    ///   - faceLandmarks: landmarks to use instead of Vision detection (reference data in tests).
    ///   - personMask: person mask to use instead of Vision segmentation (reference data in tests).
    ///   - subjectMask: subject mask to use instead of Vision foreground segmentation (tests).
    public init(image: CIImage, context: CIContext = RenderContext.analysis, faceLandmarks: [FaceLandmarks]? = nil, personMask: CIImage? = nil, bodyPoses: [BodyPose]? = nil, subjectMask: CIImage? = nil, mattes: SemanticMattes = SemanticMattes()) {
        self.source = image
        let extent = image.extent
        self.mattes = SemanticMattes(
            hair: mattes.hair.map { Self.stretch($0, over: extent) },
            skin: mattes.skin.map { Self.stretch($0, over: extent) },
            teeth: mattes.teeth.map { Self.stretch($0, over: extent) },
            sky: mattes.sky.map { Self.stretch($0, over: extent) }
        )
        self.context = context
        self.knownLandmarks = faceLandmarks
        self.knownPoses = bodyPoses
        self.knownSubject = subjectMask.map { Self.stretch($0, over: image.extent) }
        if let personMask {
            self.cachedPerson = .some(Self.stretch(personMask, over: image.extent))
        }
    }

    /// Stretches a mask (any extent) over `extent`.
    static func stretch(_ mask: CIImage, over extent: CGRect) -> CIImage {
        mask
            .transformed(by: CGAffineTransform(translationX: -mask.extent.minX, y: -mask.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: extent.width / max(mask.extent.width, 1), y: extent.height / max(mask.extent.height, 1)))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    /// Local average brightness (guided-filter coefficients of log luminance, large radius).
    public var toneBase: CIImage {
        lock.lock()
        defer { lock.unlock() }
        if let cachedToneBase { return cachedToneBase }
        let result = Self.logLuminanceCoefficients(source, workingSize: 512, radiusFraction: 0.03, eps: 0.12, context: context)
        cachedToneBase = result
        return result
    }

    /// Mid-scale local brightness for Clarity (smaller radius).
    public var clarityBase: CIImage {
        lock.lock()
        defer { lock.unlock() }
        if let cachedClarityBase { return cachedClarityBase }
        let result = Self.logLuminanceCoefficients(source, workingSize: 1024, radiusFraction: 0.008, eps: 0.05, context: context)
        cachedClarityBase = result
        return result
    }

    public var haze: HazeAnalysis {
        lock.lock()
        defer { lock.unlock() }
        if let cachedHaze { return cachedHaze }
        let result = Self.computeHaze(source, context: context)
        cachedHaze = result
        return result
    }

    /// Faces found in the photo (landmarks, skin tone, feature masks), left to right.
    public var faces: [FaceInfo] {
        lock.lock()
        defer { lock.unlock() }
        if let cachedFaces { return cachedFaces }
        let result = FaceAnalyzer.analyze(source, landmarks: knownLandmarks, context: context)
        cachedFaces = result
        return result
    }

    /// Soft mask of people in the photo (Vision person segmentation), over the analyzed image's
    /// extent, or nil if segmentation isn't available.
    public var personMask: CIImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cachedPerson { return cachedPerson }
        let result = PersonSegmenter.mask(for: source, context: context)
        cachedPerson = .some(result)
        return result
    }

    /// People in the photo with their measured outlines, left to right.
    public var bodies: [BodyShape] {
        let mask = personMask
        lock.lock()
        defer { lock.unlock() }
        if let cachedBodies { return cachedBodies }
        let poses = knownPoses ?? BodyAnalyzer.detect(in: source)
        let size = source.extent.size
        let result = poses.compactMap { BodyAnalyzer.shape(for: $0, personMask: mask, imageSize: size, image: source, context: context) }
        cachedBodies = result
        return result
    }

    /// Vision's foreground objects (nil when segmentation isn't available).
    public var subject: SubjectAnalysis? {
        lock.lock()
        defer { lock.unlock() }
        if let cachedSubject { return cachedSubject }
        let result = knownSubject == nil ? SubjectSegmenter.analyze(source, context: context) : nil
        cachedSubject = .some(result)
        return result
    }

    /// Soft mask of the main subject(s) over the analyzed extent: Vision's foreground objects,
    /// falling back to people.
    public var subjectMask: CIImage? {
        if let knownSubject { return knownSubject }
        if let all = subject?.allMask { return all }
        return personMask
    }

    /// Soft mask of the foreground objects under normalized points (y up).
    public func objectMask(at points: [SIMD2<Double>]) -> CIImage? {
        guard !points.isEmpty else { return nil }
        // Injected (test) subject masks stand in for every object.
        if let knownSubject { return knownSubject }
        guard let subject else { return nil }
        return subject.mask(instances: subject.instances(at: points))
    }

    /// Guided-filter coefficients of the sky mask over the analyzed extent, nil when there's no sky.
    public var skyCoefficients: CIImage? {
        let person = personMask
        lock.lock()
        defer { lock.unlock() }
        if let cachedSky { return cachedSky }
        let result: CIImage?
        if let matte = mattes.sky {
            result = SkyDetector.coefficients(fromMatte: matte, image: source, context: context)
        } else {
            result = SkyDetector.coefficients(source, person: person, context: context)
        }
        cachedSky = .some(result)
        return result
    }

    /// The photo's typical brightness (median perceptual luminance, kept within 0.3...0.65):
    /// contrast pivots around it so the overall brightness doesn't change.
    public var tonalPivot: Float {
        lock.lock()
        if let cachedPivot {
            lock.unlock()
            return cachedPivot
        }
        lock.unlock()
        let read = RenderContext.readFloats(ImageSource.scaled(source, maxDimension: 128), context: context)
        var values: [Float] = []
        values.reserveCapacity(read.width * read.height)
        for i in 0..<(read.width * read.height) {
            let y = 0.2126 * read.pixels[i * 4] + 0.7152 * read.pixels[i * 4 + 1] + 0.0722 * read.pixels[i * 4 + 2]
            values.append(pow(max(y, 0), 1 / 2.2))
        }
        values.sort()
        let median = values.isEmpty ? 0.5 : values[values.count / 2]
        let pivot = min(max(median, 0.3), 0.65)
        lock.lock()
        cachedPivot = pivot
        lock.unlock()
        return pivot
    }

    /// Normalized bounds of the sky (nil when there's no sky).
    public var skyRegion: CGRectValue? {
        let coefficients = skyCoefficients
        lock.lock()
        if let cachedSkyRegion {
            lock.unlock()
            return cachedSkyRegion
        }
        lock.unlock()
        var result: CGRectValue?
        if let coefficients {
            let mask = Kernels.guidedMask.apply(source, GuidedFilter.upsample(coefficients, to: source.extent))
            result = RenderPipeline.maskBounds(mask)
        }
        lock.lock()
        cachedSkyRegion = .some(result)
        lock.unlock()
        return result
    }

    /// Blemish spots on one face (cached).
    func blemishSpots(faceIndex: Int) -> [BlemishDetector.Spot] {
        let faces = self.faces
        guard faceIndex < faces.count else { return [] }
        lock.lock()
        if let cached = cachedBlemishes[faceIndex] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let spots = BlemishDetector.spots(on: faces[faceIndex], image: source, context: context)
        lock.lock()
        cachedBlemishes[faceIndex] = spots
        lock.unlock()
        return spots
    }

    /// Hair over the analyzed extent: the photo's hair matte when it has one, otherwise grown
    /// from each face's hair color (follows ponytails and long hair). Nil without faces.
    public var hairMask: CIImage? {
        if let matte = mattes.hair { return matte }
        let faces = self.faces
        let person = personMask
        lock.lock()
        if let cachedHair {
            lock.unlock()
            return cachedHair
        }
        lock.unlock()
        let result = HairSegmenter.mask(faces: faces, person: person, image: source, context: context)
        lock.lock()
        cachedHair = .some(result)
        lock.unlock()
        return result
    }

    /// Normalized bounds of the hair (for ombré), nil without a hair mask.
    public var hairRegion: CGRectValue? {
        guard let mask = hairMask else { return nil }
        lock.lock()
        if let cachedHairRegion {
            lock.unlock()
            return cachedHairRegion
        }
        lock.unlock()
        let bounds = RenderPipeline.maskBounds(mask)
        lock.lock()
        cachedHairRegion = .some(bounds)
        lock.unlock()
        return bounds
    }

    /// True once face detection has run (so the UI can show results without blocking).
    public var hasAnalyzedFaces: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cachedFaces != nil
    }

    /// Size of the analyzed image (the preview proxy).
    public var imageSize: CGSize { source.extent.size }

    /// Memoized warp fields (computing MLS on every slider tick would be wasteful).
    func cachedField(key: String, build: () -> DisplacementField?) -> DisplacementField? {
        lock.lock()
        if let field = warpCache[key] {
            lock.unlock()
            return field
        }
        lock.unlock()
        guard let field = build() else { return nil }
        lock.lock()
        if warpCache.count > 64 { warpCache.removeAll() }
        warpCache[key] = field
        lock.unlock()
        return field
    }

    /// Computes everything in advance (call from a background task).
    public func prewarm() {
        _ = toneBase
        _ = clarityBase
        _ = haze
        _ = faces
    }

    // MARK: - Computation

    private static func logLuminanceCoefficients(_ image: CIImage, workingSize: CGFloat, radiusFraction: CGFloat, eps: Float, context: CIContext) -> CIImage {
        let pair = Kernels.logLumaPair.apply(image)
        let small = ImageSource.scaled(pair, maxDimension: workingSize)
        let radius = max(2, radiusFraction * max(small.extent.width, small.extent.height))
        let coefficients = GuidedFilter.selfCoefficients(pair: small, radius: radius, eps: eps)
        return RenderContext.materialize(coefficients, context: context, format: .RGBAf)
    }

    private static func computeHaze(_ image: CIImage, context: CIContext) -> HazeAnalysis {
        let small = ImageSource.scaled(image, maxDimension: 512)
        let extent = small.extent
        let longSide = max(extent.width, extent.height)
        let dark = Kernels.darkChannel.apply(small)
        let darkMin = dark.clampedToExtent()
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: max(2, longSide * 0.006)])
            .cropped(to: extent)

        // Atmospheric light: average color of the haziest 0.2 % (largest dark-channel values).
        let darkPixels = RenderContext.readFloats(darkMin, context: context)
        let colorPixels = RenderContext.readFloats(small, context: context)
        let count = darkPixels.width * darkPixels.height
        var airlight = SIMD3<Float>(0.8, 0.8, 0.8)
        if count > 0, colorPixels.pixels.count == count * 4 {
            var indices = Array(0..<count)
            indices.sort { darkPixels.pixels[$0 * 4] > darkPixels.pixels[$1 * 4] }
            let top = max(1, count / 500)
            var sum = SIMD3<Float>(0, 0, 0)
            for index in indices.prefix(top) {
                sum += SIMD3(colorPixels.pixels[index * 4], colorPixels.pixels[index * 4 + 1], colorPixels.pixels[index * 4 + 2])
            }
            airlight = (sum / Float(top)).clamped(lowerBound: SIMD3(repeating: 0.05), upperBound: SIMD3(repeating: 4))
        }
        let airlightMax = max(airlight.x, max(airlight.y, airlight.z))

        let transmission = Kernels.transmission.apply(darkMin, airlightMax)
        let guide = Kernels.perceptualLuma.apply(small)
        // Small radius + small eps: transmission follows luminance edges closely (no halos).
        let coefficients = GuidedFilter.coefficients(guide: guide, target: transmission, radius: max(2, longSide * 0.01), eps: 0.0001)
        return HazeAnalysis(coefficients: RenderContext.materialize(coefficients, context: context, format: .RGBAf), airlight: airlight)
    }
}
