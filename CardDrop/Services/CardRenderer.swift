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

    // True 4x6 bleed size (4.25"x6.25" @ exactly 300 DPI: 1275/4.25 = 300,
    // 1875/6.25 = 300) — a genuinely different aspect ratio than the 6x9
    // bleed size above (4.25:6.25 = 0.68 vs 6.25:9.25 = 0.676), not just the
    // same canvas at a different DPI. LOB validates this ratio exactly, so
    // the 6x9-shaped front above cannot be submitted for a 4x6 order — this
    // is a second, separately-rendered forLOB-test-only front at the correct
    // 4x6 shape. Not yet wired into any real size-selection/submission flow.
    static let frontLongSideBleed4x6:  CGFloat = 1875
    static let frontShortSideBleed4x6: CGFloat = 1275

    // Back bleed margin: LOB's spec calls for 0.125in bleed on each edge
    // (see [[project_lob_specs]]). Both back canvases render at 450 DPI
    // trim size (2700x1800 for 4x6, 4050x2700 for 6x9), so this margin is
    // just applied as flat white padding post-render rather than rendering
    // the back's own content larger — the back's content is already inset
    // from every edge by borderWidth, so a plain white margin is invisible
    // against it. 0.125in * 450 DPI = 56.25pt.
    static let backBleedMarginPoints: CGFloat = 56.25

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
        guard let backRaw = bRenderer.uiImage, let backImg = paddedToBleed(backRaw) else { return nil }

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
        guard let back6x9Raw = b6x9Renderer.uiImage, let back6x9Img = paddedToBleed(back6x9Raw) else { return nil }

        draftManager.saveFront(frontImg, cardID: draft.cardID)
        draftManager.saveBack(backImg, cardID: draft.cardID)
        draftManager.saveBack6x9(back6x9Img, cardID: draft.cardID)

        return (front: frontImg, back: backImg, back6x9: back6x9Img)
    }

    // MARK: - LOB test export (on demand only — not cached, not part of any
    // real send; see [[project_lob_integration_progress]])

    enum LOBPostcardSize {
        case fourBySix
        case sixByNine
    }

    /// Renders a front+back pair sized exactly to LOB's bleed spec for the
    /// requested physical size, purely for manual LOB API testing. Nothing
    /// here is cached to disk or uploaded as part of the regular send flow —
    /// callers render fresh right before uploading, then discard.
    ///
    /// The front is composed at its native orientation (same layout as the
    /// regular `_front`, just scaled to the size-specific bleed dimensions),
    /// then rotated -90° when the draft is portrait — LOB's postcard
    /// templates are always landscape (their own 4x6 spec is 4.25"x6.25",
    /// i.e. wider than tall), so a portrait design must be rotated as a
    /// whole rather than re-flowed into a landscape canvas (which would
    /// distort/reposition its overlays instead of just turning the card).
    /// The back canvases are already always-landscape regardless of draft
    /// orientation, so no rotation is needed there.
    static func renderLOBTestExport(draft: PostcardDraft, filteredImage: UIImage?, size: LOBPostcardSize) -> (front: UIImage, back: UIImage)? {
        let (fLong, fShort): (CGFloat, CGFloat) = size == .fourBySix
            ? (frontLongSideBleed4x6, frontShortSideBleed4x6)
            : (frontLongSideBleed, frontShortSideBleed)
        let frontSize: CGSize = draft.orientation == .landscape
            ? CGSize(width: fLong, height: fShort)
            : CGSize(width: fShort, height: fLong)

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
        fRenderer.scale = 1
        guard let frontRaw = fRenderer.uiImage else { return nil }
        let frontFinal = draft.orientation == .portrait ? (rotatedMinus90(frontRaw) ?? frontRaw) : frontRaw

        let backSize = size == .fourBySix
            ? CGSize(width: longSide, height: shortSide)
            : CGSize(width: longSide6x9, height: shortSide6x9)
        let qr1Content = draft.includeBackMessageQR && !draft.backMessageQRContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? draft.backMessageQRContent
            : "https://carddropapp.com"
        let qr1Image = makeQRCode(from: qr1Content)
        let qr2Image = makeQRCode(from: "https://carddropapp.com/card/\(draft.cardID.uuidString)")

        let bRenderer: ImageRenderer<AnyView> = size == .fourBySix
            ? ImageRenderer(content: AnyView(PostcardBackCanvas(draft: draft, size: backSize, qr1Image: qr1Image, qr2Image: qr2Image, forLOB: true)))
            : ImageRenderer(content: AnyView(PostcardBackCanvas6x9(draft: draft, size: backSize, qr1Image: qr1Image, qr2Image: qr2Image, forLOB: true)))
        bRenderer.proposedSize = ProposedViewSize(backSize)
        bRenderer.isOpaque = true
        bRenderer.scale = 1
        guard let backRaw = bRenderer.uiImage, let backImg = paddedToBleed(backRaw) else { return nil }

        return (front: frontFinal, back: backImg)
    }

    /// Rotates a bitmap -90° (clockwise) as a plain image transform — used
    /// to turn a portrait-composed front into the landscape shape LOB's
    /// postcard templates require, without re-flowing/distorting its content.
    private static func rotatedMinus90(_ image: UIImage) -> UIImage? {
        let newSize = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            cg.rotate(by: -.pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }

    /// Pads a trim-size back render out to bleed size with a flat white
    /// margin (see `backBleedMarginPoints`) — the back's content is already
    /// inset from every edge, so this is invisible against it.
    private static func paddedToBleed(_ image: UIImage) -> UIImage? {
        let m = backBleedMarginPoints
        let newSize = CGSize(width: image.size.width + m * 2, height: image.size.height + m * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: newSize))
            image.draw(at: CGPoint(x: m, y: m))
        }
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
