import UIKit
import Vision
import CoreImage
import ImageIO

// "Put subject in front" — on-device subject/foreground segmentation via
// Apple's Vision framework (the iOS-native equivalent of what was originally
// asked for as "ML Kit subject isolation"; Google's ML Kit Subject
// Segmentation API is Android-only, with no iOS build — see conversation).
// VNGenerateForegroundInstanceMaskRequest requires iOS 17+, which this app
// already requires as its deployment target, so no availability gating is
// needed anywhere this is called.
enum SubjectCutoutService {

    /// Runs subject segmentation on `image` and returns a same-pixel-size,
    /// alpha-masked cutout (background made fully transparent) — or nil if
    /// no subject was found or segmentation failed for any reason. Per spec,
    /// callers treat nil as "leave the card unchanged, no error shown."
    /// Synchronous and can take up to ~a second on a full-resolution photo —
    /// always call this off the main thread.
    static func generateCutout(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        let request = VNGenerateForegroundInstanceMaskRequest()

        do {
            try handler.perform([request])
            guard let observation = request.results?.first,
                  !observation.allInstances.isEmpty else { return nil }

            // croppedToInstancesExtent: false — keep the output at the
            // original image's full extent (background pixels made
            // transparent) rather than cropped to the subject's own bounding
            // box, so it can be positioned with the exact same
            // imageScale/imageOffset transform as the uncut photo (see
            // PostcardDraft.renderedCutout(at:)) instead of needing its own
            // separate bounding-box coordinate mapping.
            let maskedPixelBuffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            )

            let ciImage = CIImage(cvPixelBuffer: maskedPixelBuffer)
            let context = CIContext()
            guard let outputCGImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }

            // Vision's masked-image output is already re-oriented to
            // "upright" pixel data (matching the `orientation` the handler
            // was given) — wrap it as .up rather than reapplying
            // image.imageOrientation, which would rotate it a second time.
            return UIImage(cgImage: outputCGImage, scale: image.scale, orientation: .up)
        } catch {
            return nil
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up:            self = .up
        case .upMirrored:     self = .upMirrored
        case .down:           self = .down
        case .downMirrored:   self = .downMirrored
        case .left:           self = .left
        case .leftMirrored:   self = .leftMirrored
        case .right:          self = .right
        case .rightMirrored:  self = .rightMirrored
        @unknown default:     self = .up
        }
    }
}
