import UIKit
import CoreText

// Single source of truth for the cardback message polygon (4x6 and 6x9) and
// the Core Text layout of the message inside it. Both back canvases DRAW with
// this and MessageStepView MEASURES with it, so the editor's "does it fit /
// how full is it" answer can never disagree with what actually gets printed.

struct MessagePolygon {
    struct Zone {
        let yStart: CGFloat
        let yEnd: CGFloat
        let right: CGFloat
    }

    // Canvas frame the text is drawn in (also the Core Text path's flip height).
    let maxX: CGFloat
    let maxY: CGFloat
    // Left edge is constant across all zones, so the polygon only steps on
    // the right edge.
    let leftX: CGFloat
    let topY: CGFloat
    let zones: [Zone]
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let startIndent: CGFloat

    // Core Text's own coordinate space is bottom-up, so vertices are authored
    // as (x, maxY - topDownY) — flipping the path itself, not just the
    // CGContext at draw time.
    func path(from startTopY: CGFloat) -> CGPath {
        func pt(_ x: CGFloat, _ topDownY: CGFloat) -> CGPoint {
            CGPoint(x: x, y: maxY - topDownY)
        }
        let p = CGMutablePath()
        p.move(to: pt(leftX, startTopY))
        var lastZoneEnd = startTopY
        for zone in zones where zone.yEnd > startTopY {
            let top = max(zone.yStart, startTopY)
            p.addLine(to: pt(zone.right, top))
            p.addLine(to: pt(zone.right, zone.yEnd))
            lastZoneEnd = zone.yEnd
        }
        p.addLine(to: pt(leftX, lastZoneEnd))
        p.closeSubpath()
        return p
    }

    // MARK: 4x6

    // Zone A: x 98–2570, y 58–675 (wide open); Zone C: x 98–1170, y 675–1142
    // (narrows to clear the branding band / no-ink zone).
    static func fourBySix(font: CardbackMessageFont) -> MessagePolygon {
        MessagePolygon(
            maxX: 2570,
            maxY: 1142,
            leftX: 98,
            topY: 58,
            zones: [
                Zone(yStart: 58,  yEnd: 675,  right: 2570),
                Zone(yStart: 675, yEnd: 1142, right: 1170)
            ],
            fontSize:   font == .print ? 84 : 98,
            lineHeight: font == .print ? 86 : 97,
            startIndent: 50
        )
    }

    // MARK: 6x9

    // Native 6x9 back is 4050x2700. The polygon's obstacle edges depend on
    // the band's position (itself derived from the no-ink zone), and the
    // PRINT/SCRIPT geometries were tuned independently — see
    // PostcardBackCanvas6x9 for the history.
    static let native6x9Size = CGSize(width: 4050, height: 2700)

    struct SixByNine {
        let polygon: MessagePolygon
        let bandOffsetX: CGFloat
        let bandOffsetY: CGFloat
    }

    static func sixByNine(font: CardbackMessageFont, size: CGSize) -> SixByNine {
        let w = size.width
        let noInkWidth = w * (4.0 / 9.0)
        let noInkLeft  = w * (1 - (4.0 / 9.0 + 0.15 / 9.0))

        let bandDesignW: CGFloat = 1100
        let bandScale: CGFloat = 0.9
        let bandW: CGFloat = bandDesignW * bandScale
        let bandX: CGFloat = 2820
        let bandY: CGFloat = 940
        let bandOffsetX: CGFloat = font == .print
            ? noInkLeft + noInkWidth - 40 - bandW
            : bandX
        let bandOffsetY: CGFloat = font == .print ? 970 : bandY

        let leftX: CGFloat = 160
        let topY:  CGFloat = font == .print ? 113  : 143
        let maxX:  CGFloat = 3910
        let maxY:  CGFloat = font == .print ? 2616 : 2646
        let noInkTop:  CGFloat = font == .print ? 1595 : 1625
        let noInkLeftEdge: CGFloat = 2200

        let polygon = MessagePolygon(
            maxX: maxX,
            maxY: maxY,
            leftX: leftX,
            topY: topY,
            zones: [
                Zone(yStart: topY,       yEnd: bandY + 3,     right: maxX),
                Zone(yStart: bandY + 3,  yEnd: noInkTop + 3,  right: bandOffsetX - 40),
                Zone(yStart: noInkTop + 3, yEnd: maxY,        right: noInkLeftEdge)
            ],
            fontSize:   font == .print ? 154 : 176,
            lineHeight: font == .print ? 164 : 179,
            startIndent: 50
        )
        return SixByNine(polygon: polygon, bandOffsetX: bandOffsetX, bandOffsetY: bandOffsetY)
    }
}

enum MessageLayout {
    // Bic Cristal ballpoint blue — muted navy, not a bright/saturated blue.
    static let inkColor = UIColor(red: 0.11, green: 0.24, blue: 0.45, alpha: 1)

    struct Result {
        let frame: CTFrame
        // Whole message is visible inside the polygon.
        let fits: Bool
        // Height of the laid-out text block ÷ the polygon's full height,
        // 0...1 (a vertical-space measure, not a character-count one).
        let fill: CGFloat
    }

    // Start at a fixed position (line 2's slot, still inside the wide top
    // zone), indented, so typing always begins in the same spot rather than
    // jumping around with message length. Only fall back to the full
    // top-anchored area (no indent) when the message wouldn't otherwise fit.
    static func layout(text: String, polygon: MessagePolygon, fontStyle: CardbackMessageFont) -> Result {
        let font = UIFont(name: fontStyle.uiFontName, size: polygon.fontSize)
            ?? UIFont.systemFont(ofSize: polygon.fontSize)
        let length = (text as NSString).length

        func makeFrame(startTopY: CGFloat, indent: CGFloat) -> (CTFrame, Int) {
            let style = NSMutableParagraphStyle()
            style.minimumLineHeight = polygon.lineHeight
            style.maximumLineHeight = polygon.lineHeight
            style.firstLineHeadIndent = indent
            let attr = NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: inkColor,
                    .paragraphStyle: style
                ]
            )
            let framesetter = CTFramesetterCreateWithAttributedString(attr)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), polygon.path(from: startTopY), nil)
            return (frame, CTFrameGetVisibleStringRange(frame).length)
        }

        let startY = polygon.topY + polygon.lineHeight
        let (startFrame, startVisible) = makeFrame(startTopY: startY, indent: polygon.startIndent)
        let frame: CTFrame
        let visible: Int
        if startVisible >= length {
            frame = startFrame
            visible = startVisible
        } else {
            (frame, visible) = makeFrame(startTopY: polygon.topY, indent: 0)
        }

        let fits = visible >= length
        // Only whole lines fit, so capacity is the whole-line count, not the
        // raw polygon height — otherwise a full card tops out below 100%.
        let rawHeight = (polygon.zones.last?.yEnd ?? polygon.maxY) - polygon.topY
        let fullHeight = floor(rawHeight / polygon.lineHeight) * polygon.lineHeight
        // Lines are fixed-height (min == max line height), so the block's
        // height is exactly lineCount × lineHeight.
        let lineCount = CFArrayGetCount(CTFrameGetLines(frame))
        let fill: CGFloat = fullHeight > 0
            ? min(1, CGFloat(lineCount) * polygon.lineHeight / fullHeight)
            : 0
        return Result(frame: frame, fits: fits, fill: fill)
    }

    // Measures a message against BOTH card sizes for one font: it must fit
    // in each, and the fuller of the two sets the displayed percentage.
    static func measure(_ message: String, font: CardbackMessageFont) -> (fits: Bool, fill: CGFloat) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return (true, 0) }
        let a = layout(text: text, polygon: .fourBySix(font: font), fontStyle: font)
        let b = layout(text: text,
                       polygon: MessagePolygon.sixByNine(font: font, size: MessagePolygon.native6x9Size).polygon,
                       fontStyle: font)
        return (a.fits && b.fits, max(a.fill, b.fill))
    }
}
