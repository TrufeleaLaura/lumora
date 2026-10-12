import CoreImage
import CoreImage.CIFilterBuiltins

/// Synthetic test images, so render tests don't depend on downloaded photos.
enum TestImages {
    /// Top half: saturated and skin-tone patches. Bottom half: black → white ramp.
    static func colorChart(size: CGSize = CGSize(width: 720, height: 480)) -> CIImage {
        let half = size.height / 2

        let ramp = CIFilter.linearGradient()
        ramp.point0 = CGPoint(x: 0, y: 0)
        ramp.point1 = CGPoint(x: size.width, y: 0)
        ramp.color0 = CIColor(red: 0, green: 0, blue: 0)
        ramp.color1 = CIColor(red: 1, green: 1, blue: 1)
        var image = ramp.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: size.width, height: half))

        let patches: [CIColor] = [
            CIColor(red: 0.80, green: 0.15, blue: 0.15),
            CIColor(red: 0.90, green: 0.60, blue: 0.15),
            CIColor(red: 0.85, green: 0.80, blue: 0.20),
            CIColor(red: 0.20, green: 0.65, blue: 0.25),
            CIColor(red: 0.15, green: 0.45, blue: 0.80),
            CIColor(red: 0.55, green: 0.25, blue: 0.70),
            CIColor(red: 0.87, green: 0.68, blue: 0.57), // light skin
            CIColor(red: 0.55, green: 0.38, blue: 0.28), // deep skin
            CIColor(red: 0.50, green: 0.50, blue: 0.50), // mid grey
        ]
        let width = size.width / CGFloat(patches.count)
        for (index, color) in patches.enumerated() {
            let rect = CGRect(x: CGFloat(index) * width, y: half, width: width, height: half)
            image = CIImage(color: color).cropped(to: rect).composited(over: image)
        }
        return image
    }
}
