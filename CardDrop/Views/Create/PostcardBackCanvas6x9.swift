import SwiftUI

// MARK: - Postcard Back Canvas (6x9 alternate layout)
//
// Alternate LOB-print-only cardback for the 6x9 postcard (9"x6" landscape
// trim) — built alongside PostcardBackCanvas.swift (the existing 4x6/6x4
// design) rather than replacing it. The two sizes have genuinely different
// no-ink zone geometry (per LOB's own templates) AND a different branding
// placement: here the band sits top-right, stacked directly above the
// no-ink zone (matching/flush its width and right edge), instead of
// bottom-left like the 4x6 back. That's a structurally different message
// polygon too (one obstacle column on the right vs. two separate notches),
// so this is kept as a fully independent view/file rather than a branch
// inside the existing one — nothing here can affect the 4x6 back.
//
// Not yet wired into CardRenderer/the send flow/draft model — same
// "prep, not connected yet" status as PostcardBackCanvas's own `forLOB` flag,
// since the LOB submission step (and any postcard-size choice) doesn't
// exist yet.
struct PostcardBackCanvas6x9: View {
    @ObservedObject var draft: PostcardDraft
    let size: CGSize
    let qr1Image: UIImage?
    let qr2Image: UIImage?
    var forLOB: Bool = false

    // LOB's 6x9 template (9"x6" landscape trim): 4" x 2.375" ink-free zone,
    // inset 0.15" from the right edge and 0.125" from the bottom edge.
    // Expressed as fractions of card width/height (not raw inches) so this
    // stays correct if `size` is ever rendered at something other than the
    // 450 DPI / 4050x2700 this was designed against.
    private let inkFreeWidthFraction:  CGFloat = 4.0    / 9.0
    private let inkFreeHeightFraction: CGFloat = 2.375  / 6.0
    private let inkFreeRightInset:     CGFloat = 0.15   / 9.0
    private let inkFreeBottomInset:    CGFloat = 0.125  / 6.0

    private let borderWidth: CGFloat = 54

    var body: some View {
        let w  = size.width
        let h  = size.height
        let bw = borderWidth

        // No-ink zone (LOB address block) — anchored from the card's right
        // and bottom edges, same corner-anchoring approach as the 4x6 back.
        let noInkWidth  = w * inkFreeWidthFraction
        let noInkHeight = h * inkFreeHeightFraction
        let noInkLeft   = w * (1 - (inkFreeWidthFraction + inkFreeRightInset))
        let noInkTop    = h * (1 - (inkFreeHeightFraction + inkFreeBottomInset))

        // Branding band — same absolute size as the 4x6 back's band (not
        // rescaled to the no-ink zone's width). Positioned so its
        // bottom-right corner sits 18px above and 18px to the left of the
        // no-ink zone's top-right corner.
        let bandDesignW: CGFloat = 1100
        let bandDesignH: CGFloat = bandDesignW * 4 / 6 - 56 - 15
        let bandScale: CGFloat = 0.9
        let bandW: CGFloat = bandDesignW * bandScale
        let bandH: CGFloat = bandDesignH * bandScale
        let bandX: CGFloat = 2820
        let bandY: CGFloat = 940
        // Band's actual drawn position. PRINT computes it from the no-ink
        // zone (right edge flush with the gray rectangle's right edge, which
        // is itself inset 40px from the raw no-ink zone's right edge — see
        // InkZoneContent6x9); SCRIPT uses the original fixed bandX/bandY —
        // the two fonts' message-polygon geometry were tuned independently
        // (saved 2026-09-09 for SCRIPT, 2026-09-25 for PRINT) and were never
        // reconciled to share one band-position formula, so this keeps each
        // exactly as it was measured rather than guessing they're equivalent.
        let geometry = MessagePolygon.sixByNine(font: draft.messageFont, size: size)
        let bandOffsetX = geometry.bandOffsetX
        let bandOffsetY = geometry.bandOffsetY

        ZStack(alignment: .topLeading) {
            Color.white

            BrandingBand6x9(qr2Image: qr2Image, width: bandDesignW, height: bandDesignH, borderWidth: bw)
                .frame(width: bandDesignW, height: bandDesignH)
                .scaleEffect(bandScale)
                .frame(width: bandW, height: bandH)
                .offset(x: bandOffsetX, y: bandOffsetY)

            let message = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                MessagePolygonLabel6x9(
                    text: message,
                    polygon: geometry.polygon,
                    fontStyle: draft.messageFont
                )
            }

            // Digital-only ink-free-zone content — skipped for a physical
            // LOB send, which needs this area blank for the mailing address.
            if !forLOB {
                InkZoneContent6x9(
                    salutation: draft.greetingSalutation,
                    phrase: draft.phraseText,
                    closing: draft.greetingClosing,
                    zoneLeft: noInkLeft,
                    zoneTop: noInkTop,
                    zoneWidth: noInkWidth,
                    zoneHeight: noInkHeight,
                    cardWidth: w,
                    cardHeight: h,
                    fontStyle: draft.messageFont
                )
            }
        }
        .frame(width: w, height: h)
    }
}

// MARK: - Ink-free zone content (duplicated from PostcardBackCanvas's
// private InkZoneContent — same absolute tuning constants read fine against
// this zone since its HEIGHT is identical in inches to the 4x6 back's zone;
// only the width is more generous here)

private struct InkZoneContent6x9: View {
    let salutation: String
    let phrase: String
    let closing: String
    let zoneLeft: CGFloat
    let zoneTop: CGFloat
    let zoneWidth: CGFloat
    let zoneHeight: CGFloat
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    // Only the font family varies with this — size/line-height are unchanged
    // between PRINT and SCRIPT for this text, same as the 4x6 back's
    // InkZoneContent.
    let fontStyle: CardbackMessageFont

    private let inkColor = Color(red: 0.11, green: 0.24, blue: 0.45)
    private let inkUIColor = UIColor(red: 0.11, green: 0.24, blue: 0.45, alpha: 1)

    private let fontSize: CGFloat = 140
    private let inkLineHeight: CGFloat = 139
    private let phraseSideMargin: CGFloat = 250

    private var sharedFont: UIFont {
        UIFont(name: fontStyle.uiFontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.gray.opacity(0.1))
                .frame(width: max(zoneWidth - 80, 0), height: max(zoneHeight - 80, 0))
                .position(x: zoneLeft + zoneWidth / 2, y: zoneTop + zoneHeight / 2)

            if !salutation.isEmpty {
                let salX = zoneLeft + 150
                let salY = zoneTop + 100
                let salFrameW = cardWidth - salX
                let salFrameH: CGFloat = 200
                InkTextCanvasLabel6x9(text: salutation, font: sharedFont, lineHeight: inkLineHeight, color: inkUIColor, alignment: .left)
                    .frame(width: salFrameW, height: salFrameH)
                    .rotationEffect(.degrees(-3), anchor: .leading)
                    .position(x: salX + salFrameW / 2, y: salY + salFrameH / 2)
            }
            if !phrase.isEmpty {
                InkTextCanvasLabel6x9(text: phrase, font: sharedFont, lineHeight: inkLineHeight, color: inkUIColor, alignment: .center)
                    .frame(width: max(zoneWidth - 2 * phraseSideMargin, 0), height: 400)
                    .rotationEffect(.degrees(-2))
                    .position(x: zoneLeft + zoneWidth / 2, y: zoneTop + zoneHeight / 2)
            }
            if !closing.isEmpty {
                let closeX = zoneLeft + zoneWidth * 0.3
                let closeFrameW = cardWidth - closeX
                let closeFrameH: CGFloat = 200
                let closeBottomY = (zoneTop + zoneHeight) - 100
                InkTextCanvasLabel6x9(text: closing, font: sharedFont, lineHeight: inkLineHeight, color: inkUIColor, alignment: .left)
                    .frame(width: closeFrameW, height: closeFrameH)
                    .rotationEffect(.degrees(-3), anchor: .leading)
                    .position(x: closeX + closeFrameW / 2, y: closeBottomY - closeFrameH / 2)
            }
        }
        .foregroundColor(inkColor)
        .frame(width: cardWidth, height: cardHeight)
    }
}

private struct InkTextCanvasLabel6x9: View {
    let text: String
    let font: UIFont
    let lineHeight: CGFloat
    let color: UIColor
    let alignment: NSTextAlignment

    var body: some View {
        Canvas { context, size in
            let style = NSMutableParagraphStyle()
            style.alignment = alignment
            style.minimumLineHeight = lineHeight
            style.maximumLineHeight = lineHeight

            let attrString = NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: style
                ]
            )

            let framesetter = CTFramesetterCreateWithAttributedString(attrString)
            let constraint = CGSize(width: size.width, height: .greatestFiniteMagnitude)
            var fitSize = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRangeMake(0, 0), nil, constraint, nil
            )
            fitSize.height = min(fitSize.height, size.height)

            let originY = (size.height - fitSize.height) / 2
            let path = CGPath(rect: CGRect(x: 0, y: originY, width: size.width, height: fitSize.height), transform: nil)
            let ctFrame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)

            context.withCGContext { cgContext in
                cgContext.textMatrix = .identity
                cgContext.translateBy(x: 0, y: size.height)
                cgContext.scaleBy(x: 1, y: -1)
                CTFrameDraw(ctFrame, cgContext)
            }
        }
    }
}

// MARK: - Message area polygon (6x9)
//
// Two-zone stepped rectilinear region: Zone A (above the branding band) is
// wide open; Zone B (from the band's top edge down to the bottom margin)
// narrows once, to the band/no-ink-zone's shared left edge, clearing both
// in a single step since they're flush-stacked with identical width.
// Zones are computed fresh from live geometry in PostcardBackCanvas6x9.body
// (not hardcoded constants like the 4x6 back's), since the band's position
// is itself derived from the no-ink zone rather than a fixed value.

private struct MessagePolygonLabel6x9: View {
    let text: String
    let polygon: MessagePolygon
    let fontStyle: CardbackMessageFont

    var body: some View {
        Canvas { context, _ in
            let ctFrame = MessageLayout.layout(text: text, polygon: polygon, fontStyle: fontStyle).frame

            context.withCGContext { cgContext in
                cgContext.saveGState()
                cgContext.textMatrix = .identity
                cgContext.translateBy(x: 0, y: polygon.maxY)
                cgContext.scaleBy(x: 1, y: -1)
                CTFrameDraw(ctFrame, cgContext)
                cgContext.restoreGState()
            }
        }
        .frame(width: polygon.maxX, height: polygon.maxY)
    }
}

// MARK: - Stamp edge shape (duplicated from PostcardBackCanvas's private
// StampEdgeShape — mimics a postage stamp's perforated border)

private struct StampEdgeShape6x9: Shape {
    var scallopRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = scallopRadius

        let horizontalScallops = max(1, Int((rect.width / (r * 2)).rounded()))
        let verticalScallops   = max(1, Int((rect.height / (r * 2)).rounded()))
        let horizontalStep = rect.width / CGFloat(horizontalScallops)
        let verticalStep   = rect.height / CGFloat(verticalScallops)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        for i in 0..<horizontalScallops {
            let x = rect.minX + CGFloat(i) * horizontalStep + horizontalStep / 2
            path.addArc(center: CGPoint(x: x, y: rect.minY), radius: r,
                        startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        }
        for i in 0..<verticalScallops {
            let y = rect.minY + CGFloat(i) * verticalStep + verticalStep / 2
            path.addArc(center: CGPoint(x: rect.maxX, y: y), radius: r,
                        startAngle: .degrees(270), endAngle: .degrees(90), clockwise: false)
        }
        for i in 0..<horizontalScallops {
            let x = rect.maxX - (CGFloat(i) * horizontalStep + horizontalStep / 2)
            path.addArc(center: CGPoint(x: x, y: rect.maxY), radius: r,
                        startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        }
        for i in 0..<verticalScallops {
            let y = rect.maxY - (CGFloat(i) * verticalStep + verticalStep / 2)
            path.addArc(center: CGPoint(x: rect.minX, y: y), radius: r,
                        startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Branding Band (duplicated from PostcardBackCanvas's private
// BrandingBand — identical internal design; only the width/height passed in
// at the call site differ, which scales the whole thing uniformly)

private struct BrandingBand6x9: View {
    let qr2Image: UIImage?
    let width: CGFloat
    let height: CGFloat
    let borderWidth: CGFloat

    var body: some View {
        let qrImageSize: CGFloat = 206
        let qrPad:       CGFloat = 10
        let qrTotal:     CGFloat = qrImageSize + qrPad * 2   // 226

        let localX: CGFloat = width - borderWidth - qrTotal
        let localY: CGFloat = borderWidth

        let wordmarkSize: CGFloat = 132
        let onTheSize:    CGFloat = 72
        let lineGap:      CGFloat = 36

        let wordmarkLineHeight = UIFont.systemFont(ofSize: wordmarkSize, weight: .bold).lineHeight
        let onTheLineHeight    = UIFont.systemFont(ofSize: onTheSize, weight: .bold).lineHeight

        let textBlockHeight: CGFloat = wordmarkLineHeight + lineGap + onTheLineHeight
        let textBlockY: CGFloat = height / 2 - textBlockHeight / 2

        let textBlockX:     CGFloat = 0
        let textBlockWidth: CGFloat = localX

        ZStack(alignment: .topLeading) {
            Color.brandBlue

            if let qr2 = qr2Image {
                Image(uiImage: qr2)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: qrImageSize, height: qrImageSize)
                    .padding(qrPad)
                    .background(StampEdgeShape6x9(scallopRadius: 10).fill(Color.white))
                    .offset(x: localX, y: localY)
            }

            VStack(alignment: .center, spacing: 0) {
                CardDropWordmark(
                    size: wordmarkSize,
                    dropOffset: 30,
                    color: .white
                )
                .background(Color.clear)
                .padding(.top, -10)

                HStack(spacing: 14) {
                    Text("On.")
                    Text("The.")
                    Text("FRIDGE.")
                        .padding(.leading, 6)
                }
                .font(.system(size: onTheSize, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, lineGap)
            }
            .frame(width: textBlockWidth, height: textBlockHeight, alignment: .top)
            .offset(x: textBlockX + 40, y: textBlockY - 60 + 20)

            let scanQRLineHeight = UIFont.systemFont(ofSize: 54, weight: .semibold).lineHeight
            Text("Scan QR to Flip it and Reply")
                .font(.system(size: 54, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: textBlockWidth, alignment: .center)
                .offset(x: textBlockX + 40, y: height - 56 - scanQRLineHeight - 10 - 20 - 10)
        }
    }
}
