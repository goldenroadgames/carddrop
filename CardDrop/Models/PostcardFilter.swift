import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum PostcardFilter: String, CaseIterable {
    case none = "None"
    case bw = "B&W"
    case vivid = "Vivid"
    case warm = "Warm"
    case cool = "Cool"
    case chrome = "Chrome"
    case fade = "Fade"
    case noir = "Noir"
    case sepia = "Sepia"
    case comic = "Halftone"
    case roy = "Roy"
    case newsprint = "Newsprint"

    func apply(to image: UIImage) -> UIImage {
        guard self != .none,
              let ciImage = CIImage(image: image) else { return image }

        let context = CIContext()
        guard let outputCI = filteredImage(ciImage) else { return image }
        guard let cgImage = context.createCGImage(outputCI, from: outputCI.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    private func filteredImage(_ input: CIImage) -> CIImage? {
        switch self {
        case .none:
            return input

        case .bw:
            let filter = CIFilter.colorControls()
            filter.inputImage = input
            filter.saturation = 0
            return filter.outputImage

        case .vivid:
            let filter = CIFilter.colorControls()
            filter.inputImage = input
            filter.saturation = 1.8
            filter.contrast = 1.2
            filter.brightness = 0.05
            return filter.outputImage

        case .warm:
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = input
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: 4000, y: 0)
            return filter.outputImage

        case .cool:
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = input
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: 9000, y: 0)
            return filter.outputImage

        case .chrome:
            let filter = CIFilter.photoEffectChrome()
            filter.inputImage = input
            return filter.outputImage

        case .fade:
            let filter = CIFilter.photoEffectFade()
            filter.inputImage = input
            return filter.outputImage

        case .noir:
            let filter = CIFilter.photoEffectNoir()
            filter.inputImage = input
            return filter.outputImage

        case .sepia:
            let filter = CIFilter.sepiaTone()
            filter.inputImage = input
            filter.intensity = 0.85
            return filter.outputImage

        case .comic:
            let posterize = CIFilter.colorPosterize()
            posterize.inputImage = input
            posterize.levels = 4
            guard let posterized = posterize.outputImage else { return input }

            let halftone = CIFilter.cmykHalftone()
            halftone.inputImage = posterized
            halftone.center = CGPoint(x: input.extent.width / 2, y: input.extent.height / 2)
            halftone.width = 20
            halftone.sharpness = 0.9
            halftone.angle = 0
            halftone.grayComponentReplacement = 0
            halftone.underColorRemoval = 0
            guard let halftoned = halftone.outputImage else { return input }

            // Lift black background toward white using gamma
            let gamma = CIFilter.gammaAdjust()
            gamma.inputImage = halftoned
            gamma.power = 0.25
            return gamma.outputImage

        case .roy:
            // Step 1: Grayscale with good contrast
            let gray = CIFilter.colorControls()
            gray.inputImage = input
            gray.saturation = 0
            gray.contrast = 1.3
            guard let grayImage = gray.outputImage else { return input }

            // Step 2: Posterize to exactly 4 tonal levels
            let posterize = CIFilter.colorPosterize()
            posterize.inputImage = grayImage
            posterize.levels = 4
            guard let posterized = posterize.outputImage else { return input }

            // Step 3: Map 4 gray tones → black / blue / red / white
            // 4-pixel gradient: darkest→black, dark-mid→blue, light-mid→red, lightest→white
            let pixels: [UInt8] = [
                0,   0,   0,   255,   // black  (luminance ~0.0)
                0,   0,   180, 255,   // blue   (luminance ~0.33)
                180, 0,   0,   255,   // red    (luminance ~0.67)
                255, 255, 255, 255    // white  (luminance ~1.0)
            ]
            let colorMapCI = CIImage(
                bitmapData: Data(pixels),
                bytesPerRow: 16,
                size: CGSize(width: 4, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            let colorMap = CIFilter.colorMap()
            colorMap.inputImage = posterized
            colorMap.gradientImage = colorMapCI
            guard let colored = colorMap.outputImage else { return input }

            // Step 4: Halftone — dots naturally appear in mid-tone (red/blue) areas
            // Light areas get tiny dots (→ solid white), dark areas get huge dots (→ solid black)
            let halftone = CIFilter.cmykHalftone()
            halftone.inputImage = colored
            halftone.center = CGPoint(x: input.extent.width / 2, y: input.extent.height / 2)
            halftone.width = 20
            halftone.sharpness = 1.0
            halftone.angle = 0
            halftone.grayComponentReplacement = 0
            halftone.underColorRemoval = 0
            guard let halftoned = halftone.outputImage else { return input }

            // Step 5: Lift blacks to reveal white background between dots
            let gamma = CIFilter.gammaAdjust()
            gamma.inputImage = halftoned
            gamma.power = 0.25
            return gamma.outputImage

        case .newsprint:
            // Grayscale (not pure B&W) — reduce saturation but keep tonal range
            let gray = CIFilter.colorControls()
            gray.inputImage = input
            gray.saturation = 0
            gray.contrast = 1.0
            guard let grayImage = gray.outputImage else { return input }

            let halftone = CIFilter.dotScreen()
            halftone.inputImage = grayImage
            halftone.center = CGPoint(x: input.extent.width / 2, y: input.extent.height / 2)
            halftone.width = 20
            halftone.sharpness = 0.9
            halftone.angle = 0
            return halftone.outputImage
        }
    }
}
