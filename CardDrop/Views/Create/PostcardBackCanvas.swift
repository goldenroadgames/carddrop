import SwiftUI

struct PostcardBackCanvas: View {
    @ObservedObject var draft: PostcardDraft
    let size: CGSize
    let qr1Image: UIImage?
    let qr2Image: UIImage?

    private let inkFreeWidthFraction:  CGFloat = 3.2835 / 6.0
    private let inkFreeHeightFraction: CGFloat = 2.375  / 4.0
    private let inkFreeRightInset:     CGFloat = 0.15   / 6.0
    private let inkFreeBottomInset:    CGFloat = 0.125  / 4.0

    private let borderWidth: CGFloat = 54

    var body: some View {
        let w  = size.width
        let h  = size.height
        let bw = borderWidth

        // Branding band — overlaps border on left and bottom (same blue,
        // so the overlap is seamless). Height set to a 4x6 h:w ratio
        // against the (unchanged) width, minus 56, then shifted down so
        // its bottom edge sits flush with the card's bottom edge — fully
        // overlapping the bottom border's full width instead of just 1px.
        //
        // BrandingBand's internal content (fonts, offsets, QR size, etc.)
        // is all tuned against this design size; bandScale shrinks the
        // whole rendered band uniformly afterward, so shrinking the box
        // scales everything inside it by the same proportion without
        // touching any of those internal constants individually.
        let bandDesignW: CGFloat = 1100
        let bandDesignH: CGFloat = bandDesignW * 4 / 6 - 56 - 15
        let bandScale: CGFloat = 0.9
        let bandW: CGFloat = bandDesignW * bandScale
        let bandH: CGFloat = bandDesignH * bandScale
        let bandX: CGFloat = 53 + 10 + 10
        let bandY: CGFloat = h - bandH - 66

        // No-ink zone top-left corner (LOB ink-free area) — used to anchor
        // the hairline guides below.
        let noInkLeft = w * (1 - (inkFreeWidthFraction + inkFreeRightInset))
        let noInkTop  = h * (1 - (inkFreeHeightFraction + inkFreeBottomInset))

        ZStack(alignment: .topLeading) {
            Color.white

            // Branding band — rendered at its design size, then scaled down
            // as a whole (see comment above bandDesignW).
            BrandingBand(qr2Image: qr2Image, width: bandDesignW, height: bandDesignH, borderWidth: bw)
                .frame(width: bandDesignW, height: bandDesignH)
                .scaleEffect(bandScale)
                .frame(width: bandW, height: bandH)
                .offset(x: bandX, y: bandY)

            // Message text — single stepped polygon covering the same area
            // the old three boxes covered (notched around QR1 top-right and
            // the branding band bottom-right).
            let message = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                MessagePolygonLabel(
                    text: message,
                    boundingWidth: messageAreaMaxX,
                    boundingHeight: messageAreaMaxY
                )
            }

            // Digital-only ink-free-zone content: greeting (salutation top,
            // closing bottom) + standalone phrase, stacked between them.
            // Physical LOB sends need this zone blank for the mailing
            // address — that branch doesn't exist yet (address/LOB
            // integration is a later phase), so for now this always renders.
            InkZoneContent(
                salutation: draft.greetingSalutation,
                phrase: draft.phraseText,
                closing: draft.greetingClosing,
                width: w * inkFreeWidthFraction,
                height: h * inkFreeHeightFraction
            )
            .offset(x: noInkLeft, y: noInkTop)

            AddressHairlineGuides(
                noInkLeft: noInkLeft,
                noInkTop: noInkTop,
                bandTop: bandY,
                borderInsideRight: w - bw
            )
            .opacity(0)
        }
        .frame(width: w, height: h)
    }
}

// MARK: - Address hairline guides
//
// Marks the boundary of LOB's addressing area: a vertical line from the
// no-ink zone's top edge down to the branding band's top edge, and a
// horizontal line from the no-ink zone's top-left corner over to the
// inside edge of the border.
private struct AddressHairlineGuides: View {
    let noInkLeft: CGFloat
    let noInkTop: CGFloat
    let bandTop: CGFloat
    let borderInsideRight: CGFloat

    private let lineWidth: CGFloat = 3

    var body: some View {
        Rectangle()
            .fill(Color.black)
            .frame(width: lineWidth, height: bandTop - noInkTop)
            .offset(x: noInkLeft, y: noInkTop)

        Rectangle()
            .fill(Color.black)
            .frame(width: borderInsideRight - noInkLeft, height: lineWidth)
            .offset(x: noInkLeft, y: noInkTop)
    }
}

// MARK: - Ink-free zone content

private struct InkZoneContent: View {
    let salutation: String
    let phrase: String
    let closing: String
    let width: CGFloat
    let height: CGFloat

    // Bic Cristal ballpoint blue — matches MessagePolygonLabel's inkColor.
    private let inkColor = Color(red: 0.11, green: 0.24, blue: 0.45)

    var body: some View {
        VStack(spacing: 18) {
            if !salutation.isEmpty {
                Text(salutation)
                    .font(.custom("Caveat-SemiBold", size: 64))
            }
            if !phrase.isEmpty {
                Spacer(minLength: 0)
                Text(phrase)
                    .font(.custom("Caveat-SemiBold", size: 70))
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            if !closing.isEmpty {
                Text(closing)
                    .font(.custom("Caveat-SemiBold", size: 64))
            }
        }
        .foregroundColor(inkColor)
        .frame(width: width, height: height)
        .padding(.vertical, 12)
    }
}

// MARK: - Message area polygon
//
// Stepped rectilinear region, notched around the one remaining FIXED,
// independently-positioned obstacle that doesn't move when this polygon
// is retuned (QR1 was removed from the cardback, so Zone A/B merged into
// a single wide-open zone since there's no longer anything to clear up top):
//   No-ink zone (pink box): x ~1155–2646, y ~675–1746
// Zone boundaries are tied to that obstacle's edges, not arbitrary values:
//   Zone A: x 98–2544, y 58–675    (wide open, no top obstacle anymore)
//   Zone C: x 98–1156, y 675–1142  (narrows to clear the branding band)

private let messageAreaMaxX: CGFloat = 2544
private let messageAreaMaxY: CGFloat = 1142
private let messageAreaTopY: CGFloat = 58
private let messageAreaLeftX: CGFloat = 98

private struct MessageZone {
    let yStart: CGFloat
    let yEnd: CGFloat
    let right: CGFloat
}

// Left edge is a constant messageAreaLeftX across all zones, so the polygon
// only steps on the right edge (the no-ink-zone notch) — see
// PostcardBackCanvas.swift header comment for the zone breakdown.
private let messageZones: [MessageZone] = [
    MessageZone(yStart: 58,  yEnd: 675,  right: 2544),
    MessageZone(yStart: 675, yEnd: 1142, right: 1156)
]

// Builds the message-area polygon starting from `topY` instead of the full
// area's top (messageAreaTopY) — used to vertically center short messages
// by trimming off unused top space while keeping each remaining zone's own
// width (rather than just shifting the drawn text down, which would apply
// the wrong zone's width and risk overlapping the QR/band notches).
private func messageAreaPath(topY: CGFloat = messageAreaTopY) -> CGPath {
    // Core Text's own coordinate space is bottom-up (y increases upward),
    // so vertices are authored here as (x, maxY - topDownY) — flipping the
    // path itself, not just the CGContext at draw time — so Core Text's
    // internal notion of "top" lines up with zone A instead of zone C.
    func pt(_ x: CGFloat, _ topDownY: CGFloat) -> CGPoint {
        CGPoint(x: x, y: messageAreaMaxY - topDownY)
    }

    let p = CGMutablePath()
    p.move(to: pt(messageAreaLeftX, topY))
    var lastZoneEnd = topY
    for zone in messageZones where zone.yEnd > topY {
        let top = max(zone.yStart, topY)
        p.addLine(to: pt(zone.right, top))
        p.addLine(to: pt(zone.right, zone.yEnd))
        lastZoneEnd = zone.yEnd
    }
    p.addLine(to: pt(messageAreaLeftX, lastZoneEnd))
    p.closeSubpath()
    return p
}

// MARK: - Message label

private struct MessagePolygonLabel: View {
    let text: String
    let boundingWidth: CGFloat
    let boundingHeight: CGFloat

    private let fontSize: CGFloat = 107 // 126 * 0.85
    private let lineHeight: CGFloat = 97 // 0.91x — tuned for 3/3/6 line split across zones A/B/C

    private let startIndent: CGFloat = 50

    // Bic Cristal ballpoint blue — muted navy, not a bright/saturated blue.
    private let inkColor = UIColor(red: 0.11, green: 0.24, blue: 0.45, alpha: 1)

    var body: some View {
        Canvas { context, _ in
            let font = UIFont(name: "Caveat-SemiBold", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)

            // Start at a fixed position (line 2's slot, still inside the
            // wide Zone A), indented, instead of the very top, so typing
            // always begins in the same spot rather than jumping around
            // based on message length. Only fall back to the full
            // top-anchored area (no indent, like line 1 always has) — for
            // the rare very-long message that wouldn't otherwise fit — so
            // nothing ever gets clipped.
            let startStyle = NSMutableParagraphStyle()
            startStyle.minimumLineHeight = lineHeight
            startStyle.maximumLineHeight = lineHeight
            startStyle.firstLineHeadIndent = startIndent
            let startAttrStr = NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: inkColor,
                    .paragraphStyle: startStyle
                ]
            )
            let startFramesetter = CTFramesetterCreateWithAttributedString(startAttrStr)
            let startY = messageAreaTopY + lineHeight
            let startPath = messageAreaPath(topY: startY)
            let startFrame = CTFramesetterCreateFrame(startFramesetter, CFRangeMake(0, 0), startPath, nil)
            let visible = CTFrameGetVisibleStringRange(startFrame)
            let ctFrame: CTFrame
            if visible.length >= (startAttrStr.string as NSString).length {
                ctFrame = startFrame
            } else {
                let fallbackStyle = NSMutableParagraphStyle()
                fallbackStyle.minimumLineHeight = lineHeight
                fallbackStyle.maximumLineHeight = lineHeight
                let fallbackAttrStr = NSAttributedString(
                    string: text,
                    attributes: [
                        .font: font,
                        .foregroundColor: inkColor,
                        .paragraphStyle: fallbackStyle
                    ]
                )
                let fallbackFramesetter = CTFramesetterCreateWithAttributedString(fallbackAttrStr)
                ctFrame = CTFramesetterCreateFrame(fallbackFramesetter, CFRangeMake(0, 0), messageAreaPath(), nil)
            }

            context.withCGContext { cgContext in
                cgContext.saveGState()
                cgContext.textMatrix = .identity
                cgContext.translateBy(x: 0, y: boundingHeight)
                cgContext.scaleBy(x: 1, y: -1)
                CTFrameDraw(ctFrame, cgContext)
                cgContext.restoreGState()
            }
        }
        .frame(width: boundingWidth, height: boundingHeight)
    }
}

// MARK: - Stamp edge shape

// A rectangle with semicircular notches cut inward along all four edges,
// evenly spaced to fit the rect's actual size — mimics a postage stamp's
// perforated border.
private struct StampEdgeShape: Shape {
    var scallopRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = scallopRadius

        let horizontalScallops = max(1, Int((rect.width / (r * 2)).rounded()))
        let verticalScallops   = max(1, Int((rect.height / (r * 2)).rounded()))
        let horizontalStep = rect.width / CGFloat(horizontalScallops)
        let verticalStep   = rect.height / CGFloat(verticalScallops)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top edge, left to right — notch dips down into the rect.
        for i in 0..<horizontalScallops {
            let x = rect.minX + CGFloat(i) * horizontalStep + horizontalStep / 2
            path.addArc(center: CGPoint(x: x, y: rect.minY), radius: r,
                        startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        }

        // Right edge, top to bottom — notch dips left into the rect.
        for i in 0..<verticalScallops {
            let y = rect.minY + CGFloat(i) * verticalStep + verticalStep / 2
            path.addArc(center: CGPoint(x: rect.maxX, y: y), radius: r,
                        startAngle: .degrees(270), endAngle: .degrees(90), clockwise: false)
        }

        // Bottom edge, right to left — notch dips up into the rect.
        for i in 0..<horizontalScallops {
            let x = rect.maxX - (CGFloat(i) * horizontalStep + horizontalStep / 2)
            path.addArc(center: CGPoint(x: x, y: rect.maxY), radius: r,
                        startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        }

        // Left edge, bottom to top — notch dips right into the rect.
        for i in 0..<verticalScallops {
            let y = rect.maxY - (CGFloat(i) * verticalStep + verticalStep / 2)
            path.addArc(center: CGPoint(x: rect.minX, y: y), radius: r,
                        startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Branding Band

private struct BrandingBand: View {
    let qr2Image: UIImage?
    let width: CGFloat
    let height: CGFloat
    let borderWidth: CGFloat

    var body: some View {
        // Same qrTotal footprint (226) as always. Padding needs to be at
        // least the scallop radius (10, restored below) so the notches
        // don't cut into the QR image itself.
        let qrImageSize: CGFloat = 206
        let qrPad:       CGFloat = 10
        let qrTotal:     CGFloat = qrImageSize + qrPad * 2   // 226

        // QR pinned to the band's top-right corner, offset from both edges
        // by the same width as the blue border around the whole card.
        let localX: CGFloat = width - borderWidth - qrTotal
        let localY: CGFloat = borderWidth

        // CardDrop / "On. The. FRIDGE." font sizes, with a fixed gap between them.
        let wordmarkSize: CGFloat = 132
        let onTheSize:    CGFloat = 72
        let lineGap:      CGFloat = 36

        let wordmarkLineHeight = UIFont.systemFont(ofSize: wordmarkSize, weight: .bold).lineHeight
        let onTheLineHeight    = UIFont.systemFont(ofSize: onTheSize, weight: .bold).lineHeight

        // Vertically centered in the branding box itself.
        let textBlockHeight: CGFloat = wordmarkLineHeight + lineGap + onTheLineHeight
        let textBlockY: CGFloat = height / 2 - textBlockHeight / 2

        // Horizontally centered between the band's left edge and the QR
        // background's left edge.
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
                    .background(StampEdgeShape(scallopRadius: 10).fill(Color.white))
                    .offset(x: localX, y: localY)
            }

            VStack(alignment: .center, spacing: 0) {
                CardDropWordmark(
                    font: .system(size: wordmarkSize, weight: .bold),
                    dropOffset: 30,
                    color: .white
                )
                .background(Color.clear)
                .padding(.top, -10)

                // Individual words in an HStack with an explicit gap, rather
                // than a single string's space characters — a plain space
                // renders at an uneven visual width depending on the
                // adjacent letterforms (e.g. "The." into "FRIDGE." reads
                // tighter than "Own." into "The." even with identical space
                // characters), so this is the only way to guarantee the
                // gaps actually look equal.
                HStack(spacing: 14) {
                    Text("Own.")
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

            // Lower-right corner of the branding box, inset 56px from the
            // right edge, same vertical position as before — measured to
            // the text's BOTTOM edge (not its top), since the band's bottom
            // now sits flush with the card's bottom edge where the blue
            // border (drawn last, on top of everything) covers the outer
            // borderWidth-thick strip. Anchoring from the top instead would
            // let the text's body sink into that strip and get painted over
            // by the border.
            let scanQRLineHeight = UIFont.systemFont(ofSize: 54, weight: .semibold).lineHeight
            Text("Scan QR to Flip it and Reply")
                .font(.system(size: 54, weight: .semibold))
                .foregroundColor(.white)
                // Centered on the same horizontal span as the CardDrop
                // wordmark (which is itself center-aligned within
                // textBlockWidth), so the two share a horizontal center.
                .frame(width: textBlockWidth, alignment: .center)
                .offset(x: textBlockX + 40, y: height - 56 - scanQRLineHeight - 10 - 20 - 10)
        }
    }
}
