import CoreImage
import Foundation

/// Anchor class used to locate this framework's bundle (and its compiled `default.metallib`).
final class EngineBundleMarker {}

/// Loads the custom Metal Core Image kernels compiled into LumoraEngine.
enum Kernels {
    static let library: Data = {
        let bundle = Bundle(for: EngineBundleMarker.self)
        guard let url = bundle.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else {
            preconditionFailure("LumoraEngine: default.metallib not found in \(bundle.bundlePath)")
        }
        return data
    }()

    static func colorKernel(_ name: String) -> CIColorKernel {
        do {
            return try CIColorKernel(functionName: name, fromMetalLibraryData: library)
        } catch {
            preconditionFailure("LumoraEngine: cannot load color kernel \(name): \(error)")
        }
    }

    /// Exposure, contrast, whites, blacks and saturation in a single pass.
    static let basicTone = colorKernel("lumora_basicTone")
}
