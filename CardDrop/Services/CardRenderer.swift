import SwiftUI
import CoreImage.CIFilterBuiltins

@MainActor
struct CardRenderer {
    static let longSide: CGFloat  = 2700
    static let shortSide: CGFloat = 1800

    static func renderAndSave(draft: PostcardDraft, filteredImage: UIImage?, draftManager: DraftManager) -> (front: UIImage, back: UIImage)? {
        let frontSize: CGSize = draft.orientation == .landscape
            ? CGSize(width: longSide, height: shortSide)
            : CGSize(width: shortSide, height: longSide)

        let fRenderer = ImageRenderer(
            content: PostcardFrontCanvas(
                image: filteredImage,
                overlays: draft.textOverlays,
                qrOverlays: draft.qrOverlays,
                burstOverlays: draft.burstOverlays,
                size: frontSize,
                border: draft.border,
                orientation: draft.orientation,
                borderText: draft.borderText,
                borderFontName: draft.borderFontName,
                borderTextColor: draft.borderTextColor
            )
        )
        fRenderer.proposedSize = ProposedViewSize(frontSize)
        guard let frontImg = fRenderer.uiImage else { return nil }

        let backSize = CGSize(width: longSide, height: shortSide)
        let qr1Content = draft.includeBackMessageQR && !draft.backMessageQRContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? draft.backMessageQRContent
            : "https://carddropapp.com"
        let qr1Image = makeQRCode(from: qr1Content)
        let qr2Image = makeQRCode(from: "https://carddropapp.com/card/\(draft.cardID.uuidString)")

        let bRenderer = ImageRenderer(
            content: PostcardBackCanvas(draft: draft, size: backSize, qr1Image: qr1Image, qr2Image: qr2Image)
        )
        bRenderer.proposedSize = ProposedViewSize(backSize)
        guard let backImg = bRenderer.uiImage else { return nil }

        draftManager.saveFront(frontImg, cardID: draft.cardID)
        draftManager.saveBack(backImg, cardID: draft.cardID)

        return (front: frontImg, back: backImg)
    }

    private static func makeQRCode(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M",  forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
