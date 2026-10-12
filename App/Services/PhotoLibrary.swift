import Foundation
import Photos

enum PhotoLibraryError: Error, LocalizedError {
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Allow Lumora to add photos in Settings › Privacy › Photos."
        }
    }
}

enum PhotoLibrary {
    /// Adds an encoded image (HEIC/JPEG/PNG) to the user's photo library as a new photo.
    static func save(imageData: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryError.notAuthorized
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: imageData, options: nil)
        }
    }
}
