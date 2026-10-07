import UIKit

// Formerly generated the standalone animated flip-card HTML uploaded to the
// (now-removed) card-html bucket — superseded by the webapp's /card/[id]
// page (CardView.tsx) rendering/flipping natively. Only the image-downscale
// helper below is still used (MMS thumbnail attachment).
struct PostcardHTMLGenerator {

    // Deliberately much smaller than a full-size image — this is just a small
    // in-thread thumbnail; most recipients will see the full-size image via
    // the URL's own rich link preview instead.
    static func scaledForThumbnail(_ image: UIImage) -> UIImage { downscale(image, maxDimension: 150) }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat = 1200) -> UIImage {
        let size = image.size
        let long = max(size.width, size.height)
        guard long > maxDimension else { return image }
        let scale = maxDimension / long
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
