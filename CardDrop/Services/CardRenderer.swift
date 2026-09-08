import SwiftUI
import CoreImage.CIFilterBuiltins

@MainActor
struct CardRenderer {
    static let longSide: CGFloat  = 2700
    static let shortSide: CGFloat = 1800

    // 6x9 postcard (9"x6" landscape trim) at the same 450 DPI as the 4x6
    // back — always landscape, same convention as `backSize` below never
    // swapping for the front's orientation.
    static let longSide6x9:  CGFloat = 4050
    static let shortSide6x9: CGFloat = 2700

    // Front, grown to LOB's 6x9 bleed size (9.25"x6.25" @ exactly 300 DPI:
    // 2775/9.25 = 300, 1875/6.25 = 300) rather than the 4x6/6x9 trim size
    // above. One canvas serves both physical products: at 6x9 it's exact
    // 300 DPI bleed; reused for the smaller 4x6 product it prints at ~444
    // DPI instead of an exact 450 — a deliberate, imperceptible compromise
    // to avoid rendering two separate bleed-sized fronts. Deliberately
    // separate from longSide/shortSide, which the 4x6 BACK still uses
    // unchanged — see [[project_lob_bleed_plan]] for why the back doesn't
    // get this treatment (it'll be white-padded post-render instead, not
    // rendered larger).
    static let frontLongSideBleed:  CGFloat = 2775
    static let frontShortSideBleed: CGFloat = 1875

    static func renderAndSave(draft: PostcardDraft, filteredImage: UIImage?, draftManager: DraftManager) -> (front: UIImage, back: UIImage, back6x9: UIImage)? {
        let frontSize: CGSize = draft.orientation == .landscape
            ? CGSize(width: frontLongSideBleed, height: frontShortSideBleed)
            : CGSize(width: frontShortSideBleed, height: frontLongSideBleed)

        let fRenderer = ImageRenderer(
            content: PostcardFrontCanvas(
                image: filteredImage,
                overlays: draft.textOverlays,
                qrOverlays: draft.qrOverlays,
                burstOverlays: draft.burstOverlays,
                greetingsOverlays: draft.greetingsOverlays,
                size: frontSize,
                border: draft.border,
                orientation: draft.orientation,
                borderText: draft.borderText,
                borderFontName: draft.borderFontName,
                borderTextColor: draft.borderTextColor
            )
        )
        fRenderer.proposedSize = ProposedViewSize(frontSize)
        fRenderer.isOpaque = true
        // 1 point == 1 print pixel (see GreetingsBadgeRenderer) — without
        // this, ImageRenderer defaults to the device's display scale (2x/3x),
        // so the saved image's real pixel dimensions silently balloon past
        // the intended 2700x1800/1800x2700.
        fRenderer.scale = 1
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
        bRenderer.isOpaque = true
        bRenderer.scale = 1
        guard let backImg = bRenderer.uiImage else { return nil }

        // Alternate 6x9 back — unwired from the send flow/draft model still
        // (see PostcardBackCanvas6x9's own doc comment), but rendered and
        // saved alongside the 4x6 back here so previews can already show it.
        let back6x9Size = CGSize(width: longSide6x9, height: shortSide6x9)
        let b6x9Renderer = ImageRenderer(
            content: PostcardBackCanvas6x9(draft: draft, size: back6x9Size, qr1Image: qr1Image, qr2Image: qr2Image)
        )
        b6x9Renderer.proposedSize = ProposedViewSize(back6x9Size)
        b6x9Renderer.isOpaque = true
        b6x9Renderer.scale = 1
        guard let back6x9Img = b6x9Renderer.uiImage else { return nil }

        draftManager.saveFront(frontImg, cardID: draft.cardID)
        draftManager.saveBack(backImg, cardID: draft.cardID)
        draftManager.saveBack6x9(back6x9Img, cardID: draft.cardID)

        return (front: frontImg, back: backImg, back6x9: back6x9Img)
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
