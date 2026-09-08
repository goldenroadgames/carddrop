import SwiftUI

// MARK: - Extruded Big Word Text  (Core Text — crisp vector fill/stroke per
// layer, not stacked SwiftUI Text copies, which blur/mush at the pixel
// offsets a real extrusion depth needs.)

private struct ExtrudedBigWordText: View {
    let text: String
    let fontName: String
    let fontSize: CGFloat
    let baseColor: Color
    let shadeColor: Color
    let outlineColor: Color
    var halftoneFill: Bool = false
    var fillStripes: [Color]? = nil
    var stripesVertical: Bool = false
    var gradientStripes: Bool = false

    // A true extruded 3D block, not a flat silhouette with a shadow behind
    // it: many solid-color (shadeColor, no gradient) copies packed at a
    // sub-pixel step so the "side" of the block reads as one continuous
    // surface instead of a few discrete, gapped shadow ghosts.
    private var depthReachX: CGFloat { fontSize * 0.05 }
    private var depthReachY: CGFloat { fontSize * 0.15 }
    private var depthStepSize: CGFloat { 0.75 }   // small, fixed — not font-size-proportional, so it stays sub-pixel-dense at any size
    private var depthSteps: Int { max(1, Int((max(depthReachX, depthReachY) / depthStepSize).rounded(.up))) }

    private var normalFont: UIFont {
        UIFont(name: fontName, size: fontSize) ?? UIFont.boldSystemFont(ofSize: fontSize)
    }
    private var outlineWidth: CGFloat { max(0.825, fontSize * 0.0198) }
    // Thin outer ring around the white outline — 1/3 the white border's own
    // visible thickness (which is outlineWidth, since the white stroke's
    // line width straddles the glyph edge and only its outer half shows).
    private var outerBorderWidth: CGFloat { outlineWidth * 4 / 3 }  // doubled from 2/3
    private var outerBorderColor: CGColor { UIColor(Color.greetingsBlueDark).cgColor }

    // First letter of each word is rendered 10% larger, with its baseline
    // counter-shifted by half the capHeight difference so it lands centered
    // against the rest of the word instead of just towering above the line.
    private var styledAttributedString: NSAttributedString {
        let bigFont = UIFont(name: fontName, size: fontSize * 1.1) ?? UIFont.boldSystemFont(ofSize: fontSize * 1.1)
        let baselineShift = -(bigFont.capHeight - normalFont.capHeight) / 2

        let result = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        result.addAttribute(.font, value: normalFont, range: fullRange)

        var atWordStart = true
        var utf16Offset = 0
        for ch in text {
            let len = String(ch).utf16.count
            if ch.isWhitespace {
                atWordStart = true
            } else if atWordStart {
                let range = NSRange(location: utf16Offset, length: len)
                result.addAttribute(.font, value: bigFont, range: range)
                result.addAttribute(.baselineOffset, value: baselineShift, range: range)
                atWordStart = false
            }
            utf16Offset += len
        }
        return result
    }

    // "Sitting on a big circle" bow, spanning true clock-face angles from
    // 9:00 (left edge) to 1:30 (right edge) — 0° is the circle's own top
    // (true "12:00"), positive = clockwise, so 9:00 = -90° and 1:30 = +45°.
    // This span is NOT symmetric about 0°, so the peak (closest approach to
    // the circle's actual top) lands slightly right of center, and the
    // right end sits a bit higher than the left end — that asymmetry is the
    // real geometry of a 9:00-to-1:30 arc, not a bug.
    private var arcHeight: CGFloat { fontSize * 0.40 }
    private var arcStartAngleDeg: CGFloat { -90 }  // 9:00
    private var arcEndAngleDeg: CGFloat { 45 }     // 1:30

    // MARK: - Per-glyph layout (arced)

    private struct ArcGlyph {
        let ctFont: CTFont
        let glyph: CGGlyph
        let baseX: CGFloat
        let baseY: CGFloat   // already includes the big-letter baselineOffset shift
        let centerX: CGFloat
    }

    // Drawing glyph-by-glyph (rather than CTFrameDraw's single straight line)
    // is what makes the arc possible — each glyph gets its own vertical lift
    // based on its horizontal position, while reusing Core Text's own glyph
    // positions so the baseline-shifted big first letters stay correct.
    private func layoutArcGlyphs() -> (glyphs: [ArcGlyph], lineWidth: CGFloat, ascent: CGFloat, descent: CGFloat) {
        let ctLine = CTLineCreateWithAttributedString(styledAttributedString)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading))

        guard let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] else {
            return ([], lineWidth, ascent, descent)
        }

        var result: [ArcGlyph] = []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRangeMake(0, count), &glyphs)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetPositions(run, CFRangeMake(0, count), &positions)
            var advances = [CGSize](repeating: .zero, count: count)
            CTRunGetAdvances(run, CFRangeMake(0, count), &advances)

            let attrs = CTRunGetAttributes(run) as? [String: Any]
            let runFont = (attrs?[NSAttributedString.Key.font.rawValue] as? UIFont) ?? normalFont
            let ctFont = CTFontCreateWithFontDescriptor(runFont.fontDescriptor as CTFontDescriptor, runFont.pointSize, nil)

            for i in 0..<count {
                result.append(ArcGlyph(
                    ctFont: ctFont,
                    glyph: glyphs[i],
                    baseX: positions[i].x,
                    baseY: positions[i].y,
                    centerX: positions[i].x + advances[i].width / 2
                ))
            }
        }
        return (result, lineWidth, ascent, descent)
    }

    var body: some View {
        let (arcGlyphs, lineWidth, ascent, descent) = layoutArcGlyphs()
        let halfWidth = max(lineWidth / 2, 1)
        let pad = max(depthReachX, depthReachY) + outlineWidth + outerBorderWidth + 4

        // cos(theta) is proportional to height above the circle's own
        // center; normalized here against the LOWER of the two endpoints
        // (10:00, being farther from the true top, is always the lower one)
        // so that end sits at lift=0 and the peak (nearest true "12:00")
        // reaches the full arcHeight — the other end lands wherever its own
        // angle's cosine puts it, which is above 0 since 1:00 is closer to
        // the top than 10:00 is.
        let cosStart = cos(arcStartAngleDeg * .pi / 180)
        let cosEnd = cos(arcEndAngleDeg * .pi / 180)
        let minCos = min(cosStart, cosEnd)
        let cosRange = max(1 - minCos, 0.0001)
        let lift: (ArcGlyph) -> CGFloat = { g in
            let normalizedX = max(-1, min(1, (g.centerX - halfWidth) / halfWidth))
            let angleDeg = arcStartAngleDeg + (arcEndAngleDeg - arcStartAngleDeg) * (normalizedX + 1) / 2
            let cosTheta = cos(angleDeg * .pi / 180)
            return arcHeight * (cosTheta - minCos) / cosRange
        }

        // Reserve headroom for the actual highest-lifted glyph in THIS word,
        // not the flat arcHeight constant — a word whose peak-nearest letter
        // doesn't land exactly at the arc's true top (angle 0) reaches less
        // than the full arcHeight, and reserving the full amount regardless
        // left dead blank space above the letters that no padding cancelled.
        let maxLift = arcGlyphs.map(lift).max() ?? 0

        let canvasSize = CGSize(
            width: lineWidth + pad * 2,
            height: ascent + descent + maxLift + pad * 2
        )
        let originX = pad
        let originY = pad + descent

        let drawGlyphsIn: (CGContext) -> Void = { cg in
            for g in arcGlyphs {
                cg.saveGState()
                cg.translateBy(x: originX + g.baseX, y: originY + g.baseY + lift(g))
                var pos = CGPoint.zero
                CTFontDrawGlyphs(g.ctFont, [g.glyph], &pos, 1, cg)
                cg.restoreGState()
            }
        }

        // Real glyph outlines (not just drawn pixels) so a gradient fill can
        // be clipped exactly to the letterforms.
        let combinedGlyphPath: () -> CGPath = {
            let combined = CGMutablePath()
            for g in arcGlyphs {
                guard let glyphPath = CTFontCreatePathForGlyph(g.ctFont, g.glyph, nil) else { continue }
                var transform = CGAffineTransform(translationX: originX + g.baseX, y: originY + g.baseY + lift(g))
                if let transformed = glyphPath.copy(using: &transform) {
                    combined.addPath(transformed)
                }
            }
            return combined
        }

        return Canvas { context, size in
            context.withCGContext { cg in
                cg.textMatrix = .identity
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: 1, y: -1)

                // Extruded block side — many tightly-packed, solid shadeColor
                // copies (no gradient) stepping from the farthest point back
                // to the front face, so the "side" reads as one continuous
                // 3D surface instead of a couple of gapped shadow ghosts.
                // Farthest layer also gets the outline, tracing the block's
                // back edge; the front face's own outline (below) traces the
                // front edge — together they bound the whole extruded shape.
                // Note: this translate happens after the context's y-flip
                // above, so a positive dy here would push the layer UP the
                // screen — negate it to get the intended down-right offset.
                for i in stride(from: depthSteps, through: 1, by: -1) {
                    let t = CGFloat(i) / CGFloat(depthSteps)
                    cg.saveGState()
                    cg.translateBy(x: depthReachX * t, y: -depthReachY * t)
                    cg.setFillColor(UIColor(shadeColor).cgColor)
                    if i == depthSteps {
                        // Extrusion/"drop" edge — same darker-blue trace
                        // color as the front-facing letters' outer border,
                        // same width/pass as before (just a color swap).
                        cg.setLineWidth(outlineWidth * 2)
                        cg.setLineJoin(.round)
                        cg.setStrokeColor(outerBorderColor)
                        cg.setTextDrawingMode(.fillStroke)
                    } else {
                        cg.setTextDrawingMode(.fill)
                    }
                    drawGlyphsIn(cg)
                    cg.restoreGState()
                }

                // Front face
                if halftoneFill {
                    // Vintage-print look: clip to the real glyph outlines and
                    // fill with a 45°-angled grid of dots (like an offset/
                    // litho halftone screen) instead of a solid color — the
                    // badge color shows through the gaps between dots.
                    let path = combinedGlyphPath()
                    // Typographic bounds (from CTLineGetTypographicBounds),
                    // not the raw glyph path's geometric bounding box — a
                    // decorative display font's paths can include swash/
                    // overshoot geometry taller than the letters' actual
                    // visual height.
                    let bounds = CGRect(x: originX, y: originY - descent, width: lineWidth, height: ascent + descent)

                    // Outer darker-blue border ring, drawn first (before the
                    // dot fill) so the fill's clipped interior repaint below
                    // covers the blue's inward-bleeding half, leaving only
                    // the outward half visible outside the letters.
                    cg.saveGState()
                    cg.addPath(path)
                    cg.setLineWidth(outlineWidth * 2 + outerBorderWidth * 2)
                    cg.setLineJoin(.round)
                    cg.setStrokeColor(outerBorderColor)
                    cg.strokePath()
                    cg.restoreGState()

                    cg.saveGState()
                    cg.addPath(path)
                    cg.clip()

                    let dotRadius = fontSize * 0.023
                    let dotSpacing = dotRadius * 1.4   // less than 2x radius so dots meaningfully overlap
                    cg.translateBy(x: bounds.midX, y: bounds.midY)
                    cg.rotate(by: 45 * .pi / 180)
                    cg.translateBy(x: -bounds.midX, y: -bounds.midY)
                    cg.setFillColor(UIColor(baseColor).cgColor)
                    let coverage = max(bounds.width, bounds.height) * 1.5
                    var y = bounds.midY - coverage
                    while y < bounds.midY + coverage {
                        var x = bounds.midX - coverage
                        while x < bounds.midX + coverage {
                            cg.fillEllipse(in: CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                            x += dotSpacing
                        }
                        y += dotSpacing
                    }
                    cg.restoreGState()

                    cg.saveGState()
                    cg.addPath(path)
                    cg.setLineWidth(outlineWidth * 2)
                    cg.setLineJoin(.round)
                    cg.setStrokeColor(UIColor(outlineColor).cgColor)
                    cg.strokePath()
                    cg.restoreGState()
                } else if let stripes = fillStripes, stripes.count >= 2 {
                    // Rainbow/striped look: clip to the real glyph outlines,
                    // then paint hard-edged bands (not a blended gradient —
                    // matches vintage postcard "GREETINGS FROM" lettering,
                    // which uses distinct color bands, not a smooth fade)
                    // across the full glyph extent, either stacked
                    // left-to-right or bottom-to-top.
                    let path = combinedGlyphPath()
                    // The real glyph ink's own bounding box (not the padded
                    // canvas or the typographic line box) — bands packed
                    // against this stay tight to the letters themselves, so
                    // all N colors read within a single letter's height
                    // instead of being mostly wasted on the surrounding
                    // extrusion/outline/arc padding.
                    let inkBounds = path.boundingBoxOfPath
                    let bandCount = CGFloat(stripes.count)

                    // Outer darker-blue border ring, drawn first (before the
                    // clipped stripe/gradient fill) so that fill's full
                    // interior repaint below covers the blue's inward-
                    // bleeding half, leaving only the outward half visible
                    // outside the letters.
                    cg.saveGState()
                    cg.addPath(path)
                    cg.setLineWidth(outlineWidth * 2 + outerBorderWidth * 2)
                    cg.setLineJoin(.round)
                    cg.setStrokeColor(outerBorderColor)
                    cg.strokePath()
                    cg.restoreGState()

                    cg.saveGState()
                    cg.addPath(path)
                    cg.clip()
                    if gradientStripes {
                        // Same color order/direction as the hard-band case.
                        // Vertical (scheme5) uses a short blend zone at each
                        // band boundary instead of one single stop per color
                        // — each color holds a flat plateau across most of
                        // its own band (blendFraction of the band width is
                        // spent fading into the next color), so the bands
                        // stay readably distinct instead of smearing into
                        // one continuous blur. Horizontal (scheme6) keeps
                        // the original fully-smooth single-stop-per-color
                        // blend — untouched.
                        let cgColors: CFArray
                        let locations: [CGFloat]
                        if stripesVertical {
                            let count = stripes.count
                            let blendFraction: CGFloat = 0.5
                            var cgColorsArr: [CGColor] = []
                            var locs: [CGFloat] = []
                            for (i, color) in stripes.enumerated() {
                                let bandStart = CGFloat(i) / CGFloat(count)
                                let bandEnd = CGFloat(i + 1) / CGFloat(count)
                                let bandWidth = bandEnd - bandStart
                                let inset = bandWidth * blendFraction / 2
                                let plateauStart = i == 0 ? bandStart : bandStart + inset
                                let plateauEnd = i == count - 1 ? bandEnd : bandEnd - inset
                                let cgColor = UIColor(color).cgColor
                                cgColorsArr.append(cgColor)
                                locs.append(plateauStart)
                                cgColorsArr.append(cgColor)
                                locs.append(plateauEnd)
                            }
                            cgColors = cgColorsArr as CFArray
                            locations = locs
                        } else {
                            cgColors = stripes.map { UIColor($0).cgColor } as CFArray
                            locations = (0..<stripes.count).map { CGFloat($0) / CGFloat(stripes.count - 1) }
                        }
                        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: locations) {
                            let startPoint: CGPoint
                            let endPoint: CGPoint
                            if stripesVertical {
                                // Red (first in the array) at the top, in
                                // this y-flipped (y-increases-upward) space.
                                startPoint = CGPoint(x: inkBounds.midX, y: inkBounds.maxY)
                                endPoint = CGPoint(x: inkBounds.midX, y: inkBounds.minY)
                            } else {
                                startPoint = CGPoint(x: inkBounds.minX, y: inkBounds.midY)
                                endPoint = CGPoint(x: inkBounds.maxX, y: inkBounds.midY)
                            }
                            cg.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                        }
                    } else {
                        for (i, color) in stripes.enumerated() {
                            let bandRect: CGRect
                            if stripesVertical {
                                // This context is y-flipped (see translateBy/
                                // scaleBy above) so y increases upward — index 0
                                // (red, first in the array) needs to land at the
                                // TOP band, so its y-slot is counted from the top
                                // down rather than from y=0 at the bottom.
                                let bandHeight = inkBounds.height / bandCount
                                let slotFromTop = bandCount - 1 - CGFloat(i)
                                bandRect = CGRect(x: inkBounds.minX, y: inkBounds.minY + bandHeight * slotFromTop,
                                                   width: inkBounds.width, height: bandHeight + 0.5)
                            } else {
                                let bandWidth = inkBounds.width / bandCount
                                bandRect = CGRect(x: inkBounds.minX + bandWidth * CGFloat(i), y: inkBounds.minY,
                                                   width: bandWidth + 0.5, height: inkBounds.height)
                            }
                            cg.setFillColor(UIColor(color).cgColor)
                            cg.fill(bandRect)
                        }
                    }
                    cg.restoreGState()

                    cg.saveGState()
                    cg.addPath(path)
                    cg.setLineWidth(outlineWidth * 2)
                    cg.setLineJoin(.round)
                    cg.setStrokeColor(UIColor(outlineColor).cgColor)
                    cg.strokePath()
                    cg.restoreGState()
                } else {
                    // Outer darker-blue border, stroke-only, drawn first so
                    // the white stroke drawn after it covers all but a thin
                    // outer ring.
                    cg.saveGState()
                    cg.setLineWidth(outlineWidth * 2 + outerBorderWidth * 2)
                    cg.setLineJoin(.round)
                    cg.setStrokeColor(outerBorderColor)
                    cg.setTextDrawingMode(.stroke)
                    drawGlyphsIn(cg)
                    cg.restoreGState()

                    // Flat fill — outline + fill in one crisp pass
                    cg.saveGState()
                    cg.setLineWidth(outlineWidth * 2)
                    cg.setLineJoin(.round)
                    cg.setStrokeColor(UIColor(outlineColor).cgColor)
                    cg.setFillColor(UIColor(baseColor).cgColor)
                    cg.setTextDrawingMode(.fillStroke)
                    drawGlyphsIn(cg)
                    cg.restoreGState()
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .fixedSize()
    }
}

// MARK: - Greetings Caption View  (static — used in both editing canvas and PostcardFrontCanvas)

struct GreetingsCaptionView: View {
    let word: String
    let preset: GreetingsPreset
    let bigWordFontSize: CGFloat   // fixed, absolute — no shrink-to-fit
    let scriptFontSize: CGFloat    // fixed, absolute — solved by the caller for a target "greetings from" width
    let isLandscape: Bool          // pull (script-to-bigword overlap) differs by orientation
    var printScale: CGFloat = 1.0  // canvas-units-per-print-pixel, so fixed-print-pixel values (e.g. the script/bigword gap) land the same visually in the small live-preview canvas and the full print-resolution canvas
    var backgroundOpacity: CGFloat = 1.0
    // Overrides preset.scriptColor when set — used so "greetings from"
    // reads in black against the harvest-gold badge background instead of
    // its usual yellow, which loses contrast there.
    var scriptColorOverride: Color? = nil
    // When false, skips drawing the background rectangle entirely (used by
    // GreetingsBadgeRenderer to cache just the letters/script as a
    // transparent-background bitmap — the background rectangle is then
    // drawn separately, live, so a background-opacity slider can respond
    // instantly without invalidating/re-rendering the cached bitmap).
    var drawsBackground: Bool = true
    // When set (only for the "tilt" position), stretches the badge
    // background to this width regardless of the word's own content width —
    // content stays centered inside it via the .frame's default center
    // alignment, before the tilt rotation is applied by the caller.
    var backgroundMinWidth: CGFloat? = nil
    // When set (only for landscape tilt), left-justifies the content this
    // many print-scale px from backgroundMinWidth's left edge instead of
    // centering it — a fixed inset regardless of word length, unlike a
    // center-offset (which drifts with content width since it shifts a
    // width-dependent center point rather than pinning the left edge).
    var contentLeadingInset: CGFloat? = nil
    // Extra horizontal padding added on TOP of badgeHPad, per side (print
    // scale) — used to widen the badge for .center/.corner without
    // affecting .left/tilt, which already sizes itself via backgroundMinWidth.
    var extraHorizontalPad: CGFloat = 0

    var body: some View {
        let g = GreetingsGeometry(word: word, fontName: GreetingsGeometry.bigWordFontName, bigWordFontSize: bigWordFontSize, scriptFontSize: scriptFontSize, isLandscape: isLandscape, printScale: printScale)
        let bigWordPull = g.scriptFontSize * (isLandscape ? 0.3 : 0.3)
        let scriptPull = g.scriptFontSize * (isLandscape ? 0.35 : 0.35)
        let badgeHPad = g.bigWordFontSize * 0.06 + extraHorizontalPad * printScale
        let scriptText = "\u{00A0}\u{00A0}greetings from"

        // Top/bottom margins are both fixed at 37.5px (print scale), measured
        // to the true highest point of "greetings from" and the true lowest
        // point of the big word (extrusion drop included) — not to their
        // layout frames.
        let margin = 37.5 * printScale

        // Mirrors ExtrudedBigWordText's own internal `pad` (the blank margin
        // it reserves above/below the letters for the extrusion/outline),
        // so that margin can be cancelled out precisely on both top and
        // bottom below, in favor of the flat `margin` above/below.
        let bigWordOutlineWidth = max(0.825, g.bigWordFontSize * 0.0198)
        let bigWordDepthReachX = g.bigWordFontSize * 0.05
        let bigWordDepthReachY = g.bigWordFontSize * 0.15
        let bigWordPad = max(bigWordDepthReachX, bigWordDepthReachY) + bigWordOutlineWidth + bigWordOutlineWidth * 4 / 3 + 4

        // Pull the script line down toward the big word with a plain visual
        // offset rather than a cropped frame — offset never touches layout
        // size, so it can't accidentally collapse a sibling's space. The big
        // word stays centered (VStack's default alignment); only the script
        // line's position within its own width-matched box changes.
        VStack(alignment: .center, spacing: 0) {
            // Faux-bold: a real font weight can't go past DancingScript-Bold
            // (its heaviest named instance), so a few sub-pixel offset copies
            // thicken the strokes instead — same trick the hidden Burst
            // caption feature uses for its outline.
            ZStack {
                let boldOffset = g.scriptFontSize * 0.012
                ForEach([CGSize(width: -boldOffset, height: 0), CGSize(width: boldOffset, height: 0),
                         CGSize(width: 0, height: -boldOffset), CGSize(width: 0, height: boldOffset)], id: \.self) { o in
                    Text(scriptText).offset(o)
                }
                Text(scriptText)
            }
                .font(.custom(GreetingsGeometry.scriptFontName, size: g.scriptFontSize))
                .fontWeight(.heavy)
                .foregroundColor(scriptColorOverride ?? preset.scriptColor)
                .fixedSize()
                .frame(width: g.contentWidth, alignment: .leading)
                // Anchored to .leading (not the default .center) — the text
                // itself sits at the left edge of this contentWidth-wide
                // frame, so rotating around the frame's center would pivot
                // around a point far to the right of the actual glyphs,
                // wildly overstating how much the tilt lifts them.
                .rotationEffect(.degrees(-4), anchor: .leading)
                .offset(y: scriptPull)
                .padding(.bottom, -scriptPull)
                .padding(.top, margin)

            ExtrudedBigWordText(
                text: g.displayWord,
                fontName: GreetingsGeometry.bigWordFontName,
                fontSize: g.bigWordFontSize,
                baseColor: preset.baseColor,
                shadeColor: preset.shadeColor,
                outlineColor: preset.outlineColor,
                halftoneFill: preset.halftoneFill,
                fillStripes: preset.fillStripes,
                stripesVertical: preset.stripesVertical,
                gradientStripes: preset.gradientStripes
            )
            .padding(.top, 0)
            .padding(.bottom, isLandscape ? -175 : -155)
            .offset(y: -bigWordPull)
            .padding(.top, -bigWordPull)
        }
        .padding(.horizontal, badgeHPad)
        .padding(.bottom, margin)
        .padding(.leading, contentLeadingInset ?? 0)
        .frame(minWidth: backgroundMinWidth, alignment: contentLeadingInset != nil ? .leading : .center)
        .background {
            if drawsBackground {
                Rectangle()
                    .fill(preset.badgeColor.opacity(backgroundOpacity))
            }
        }
        .fixedSize()
    }
}

// MARK: - Interactive Item View  (drag / resize / rotate handles)

private struct GreetingsBadgeRenderKey: Equatable {
    let word: String
    let presetID: String
    let fixedPosition: GreetingsFixedPosition
    let badgeColorChoice: GreetingsBadgeColor
    let scriptColorChoice: GreetingsScriptColor?
    let isLandscape: Bool
}

struct GreetingsCaptionItemView: View {
    @Binding var overlay: GreetingsOverlay
    let canvasSize: CGSize
    let isSelected: Bool
    let onSelect: () -> Void

    // The badge is rendered once as a bitmap at the canonical print
    // resolution (see GreetingsBadgeRenderer) and simply scaled down to fit
    // this canvas — never re-derived at this canvas's own small scale — so
    // the live editor and the print bake can never drift apart.
    @State private var renderedImage: UIImage?
    @State private var renderedSize: CGSize = .zero
    @State private var renderedKey: GreetingsBadgeRenderKey?

    private var isLandscape: Bool { canvasSize.width >= canvasSize.height }
    private var referenceWidth: CGFloat { isLandscape ? 2775 : 1875 }
    // Canonical-print-pixels-per-canvas-point — scales the print-resolution
    // bitmap (and its position) down to fit this (possibly tiny) canvas.
    private var displayScale: CGFloat { canvasSize.width / referenceWidth }

    private var currentKey: GreetingsBadgeRenderKey {
        GreetingsBadgeRenderKey(word: overlay.word, presetID: overlay.presetID, fixedPosition: overlay.fixedPosition, badgeColorChoice: overlay.badgeColorChoice, scriptColorChoice: overlay.scriptColorChoice, isLandscape: isLandscape)
    }

    // Only used as a placeholder to solve initial placement for the very
    // first frame, before the real bitmap (and its exact size) is ready.
    private var fallbackSize: CGSize {
        let scriptFontSize = GreetingsGeometry.scriptFontSize(isLandscape: isLandscape, scale: 1.0)
        let bigWordFontSize = GreetingsGeometry.bigWordFontSize(forLetterHeight: 225, maxBadgeWidth: referenceWidth - GreetingsBadgeRenderer.letterEdgeClearance, word: overlay.word, fontName: GreetingsGeometry.bigWordFontName, scriptFontSize: scriptFontSize, isLandscape: isLandscape, printScale: 1.0)
        let geometry = GreetingsGeometry(word: overlay.word, fontName: GreetingsGeometry.bigWordFontName, bigWordFontSize: bigWordFontSize, scriptFontSize: scriptFontSize, isLandscape: isLandscape, printScale: 1.0)
        return geometry.estimatedBadgeSize()
    }

    var body: some View {
        let printSize = renderedKey == currentKey ? renderedSize : fallbackSize
        // "Tilt" stretches the badge to a fixed print-scale width — feed
        // that same width into the position solver so the corner-inset
        // math lines up with what's actually rendered (the real bitmap's
        // own width once available). .center/.corner are untouched.
        // +75 on top of the original 2850/1925 tilt-overshoot width — the
        // front canvas grew by that same 75px (bleed margin, see
        // CardRenderer.frontLongSideBleed/frontShortSideBleed) and this
        // band's overshoot needs to keep pace with it, or its rotated
        // projection stops covering the new wider/taller canvas edge-to-edge.
        let badgeSize: CGSize = overlay.fixedPosition == .left
            ? CGSize(width: isLandscape ? 2925 : 2000, height: printSize.height)
            : printSize
        let center = overlay.fixedPosition.center(badgeSize: badgeSize, canvasSize: CGSize(width: referenceWidth, height: referenceWidth * canvasSize.height / canvasSize.width))

        Group {
            if let img = renderedImage, renderedKey == currentKey {
                let w = renderedSize.width * displayScale
                let h = renderedSize.height * displayScale
                ZStack {
                    // Live background layer — responds to the opacity
                    // slider instantly, no re-render of the cached bitmap
                    // (which holds only the letters/script) needed.
                    Rectangle().fill(overlay.badgeColorChoice.color.opacity(overlay.backgroundOpacity))
                    Image(uiImage: img)
                        .resizable()
                }
                .frame(width: w, height: h)
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        // Selection ring
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.white : Color.clear, lineWidth: 1.5)
                .padding(-4)
        )
        .rotationEffect(Angle(degrees: overlay.fixedPosition.rotationDegrees))
        .position(x: center.x * displayScale, y: center.y * displayScale)
        .onTapGesture { onSelect() }
        .task(id: currentKey) {
            guard let result = GreetingsBadgeRenderer.render(overlay: overlay, isLandscape: isLandscape) else { return }
            renderedImage = result.image
            renderedSize = result.size
            renderedKey = currentKey
        }
    }
}

// MARK: - Color Swatch  (shows a preset's 3-color scheme — fill / depth / script)

struct GreetingsColorSwatch: View {
    let preset: GreetingsPreset
    let isSelected: Bool

    var body: some View {
        ZStack {
            if let stripes = preset.fillStripes, stripes.count >= 2 {
                if preset.gradientStripes {
                    // Real gradient preview, same direction as the actual
                    // render, rather than hard-masked wedges.
                    Circle()
                        .fill(LinearGradient(
                            gradient: Gradient(colors: stripes),
                            startPoint: preset.stripesVertical ? .top : .leading,
                            endPoint: preset.stripesVertical ? .bottom : .trailing
                        ))
                        .frame(width: 26, height: 26)
                        .offset(x: -6, y: -4)
                } else {
                    // Thin wedges fanning out from center so the swatch reads
                    // as striped rather than a single blended color — banded
                    // the same direction as the actual render (vertical
                    // schemes get horizontal bands stacked top-to-bottom;
                    // horizontal schemes get vertical bands side-by-side).
                    let bandSize: CGFloat = 26 / CGFloat(stripes.count)
                    ForEach(Array(stripes.enumerated()), id: \.offset) { i, color in
                        let slot = CGFloat(i) - CGFloat(stripes.count - 1) / 2
                        Circle().fill(color)
                            .frame(width: 26, height: 26)
                            .mask(
                                Rectangle()
                                    .frame(width: preset.stripesVertical ? 26 : bandSize,
                                           height: preset.stripesVertical ? bandSize : 26)
                                    .offset(x: preset.stripesVertical ? 0 : slot * bandSize,
                                            y: preset.stripesVertical ? slot * bandSize : 0)
                            )
                    }
                    .offset(x: -6, y: -4)
                }
            } else {
                Circle().fill(preset.baseColor).frame(width: 26, height: 26)
                    .offset(x: -6, y: -4)
            }
            Circle().fill(preset.shadeColor).frame(width: 18, height: 18)
                .offset(x: 9, y: 6)
            Circle().fill(preset.scriptColor).frame(width: 12, height: 12)
                .offset(x: -10, y: 11)
        }
        .frame(width: 44, height: 44)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 999))
        .overlay(
            RoundedRectangle(cornerRadius: 999)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.25),
                        lineWidth: isSelected ? 2.5 : 1)
        )
    }
}

// MARK: - Edit Panel

struct GreetingsCaptionEditPanel: View {
    @Binding var overlay: GreetingsOverlay
    var onDelete: () -> Void
    var onDone: () -> Void

    @FocusState private var textFocused: Bool
    private let charLimit = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Row 1: "Greetings from" label + word input + script text color swatches
            HStack(spacing: 8) {
                Text("Greetings from").font(.caption).foregroundColor(.secondary)

                TextField("Mom, Missouri, Buddy…", text: $overlay.word)
                    .textFieldStyle(.roundedBorder)
                    .focused($textFocused)
                    .onChange(of: overlay.word) { _, new in
                        if new.count > charLimit { overlay.word = String(new.prefix(charLimit)) }
                    }

                HStack(spacing: 6) {
                    ForEach(GreetingsScriptColor.allCases) { choice in
                        // Nothing is highlighted until the user explicitly
                        // taps a swatch — until then the scheme's own
                        // default color is in effect but unmarked here.
                        let isSelected = overlay.scriptColorChoice == choice
                        Circle()
                            .fill(choice.color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(isSelected ? 0.8 : 0.15),
                                            lineWidth: isSelected ? 2.5 : 1)
                            )
                            .onTapGesture { overlay.scriptColorChoice = choice }
                    }
                }
            }

            // Row 2: Color Options
            HStack(spacing: 8) {
                Text("Color Options").font(.caption).foregroundColor(.secondary)
                ForEach(GreetingsPreset.all) { preset in
                    GreetingsColorSwatch(preset: preset, isSelected: preset.id == overlay.presetID)
                        .onTapGesture {
                            overlay.presetID = preset.id
                            // A new color scheme resets the script color back
                            // to that scheme's own default until the user
                            // explicitly picks a swatch again.
                            overlay.scriptColorChoice = nil
                        }
                }
            }

            // Row 3: Position — 3 mutually exclusive buttons
            HStack(spacing: 8) {
                Text("Position").font(.caption).foregroundColor(.secondary)
                ForEach(GreetingsFixedPosition.allCases, id: \.self) { pos in
                    Button(pos.displayName) { overlay.fixedPosition = pos }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(overlay.fixedPosition == pos ? Color.accentColor : Color(.secondarySystemBackground))
                        .foregroundColor(overlay.fixedPosition == pos ? .white : .primary)
                        .cornerRadius(999)
                }
            }

            // Row 4: background opacity — full right (1.0) is fully opaque,
            // full left (0.0) is a fully clear background — plus badge
            // background color dots, mutually exclusive (picking one turns
            // off whichever was previously selected).
            HStack(spacing: 8) {
                Text("Background").font(.caption).foregroundColor(.secondary)
                Slider(value: $overlay.backgroundOpacity, in: 0...1)
                HStack(spacing: 6) {
                    ForEach(GreetingsBadgeColor.allCases) { choice in
                        Circle()
                            .fill(choice.color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(overlay.badgeColorChoice == choice ? 0.8 : 0.15),
                                            lineWidth: overlay.badgeColorChoice == choice ? 2.5 : 1)
                            )
                            .onTapGesture { overlay.badgeColorChoice = choice }
                    }
                }
            }

            // Row 5: Done / Delete — on their own line, below the rest of
            // the controls rather than crowding the word-input row.
            HStack(spacing: 8) {
                Button("Done", action: onDone)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(999)

                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundColor(.red)
                }
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
}
