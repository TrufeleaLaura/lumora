import CoreImage
import Metal

/// Shared GPU and Core Image state. Creating a CIContext is expensive, so the app uses one.
public enum RenderContext {
    public static let device: MTLDevice? = MTLCreateSystemDefaultDevice()

    /// Linear, extended-range working space: edits happen in scene-linear light, in half floats.
    public static let workingColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    public static let linearSRGB = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    public static let linearDisplayP3 = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
    public static let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!
    public static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    public static let shared: CIContext = {
        let options: [CIContextOption: Any] = [
            .workingColorSpace: workingColorSpace,
            .workingFormat: NSNumber(value: CIFormat.RGBAh.rawValue),
        ]
        if let device {
            return CIContext(mtlDevice: device, options: options)
        }
        return CIContext(options: options)
    }()
}
