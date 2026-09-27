import SwiftUI

// MARK: - Greetings Color Palette

extension Color {
    // "Greetings from" is yellow across every color scheme
    static let greetingsScriptYellow = Color(red: 0.98, green: 0.82, blue: 0.25)

    // Named brand colors for the Greetings badges. Boosted ~25% saturation
    // from the originally-specified hex values (kept as comments) — same
    // hues/lightness, richer chroma, still in the muted "heritage" family
    // rather than pushed to full vivid primaries.
    static let greetingsBlue  = Color(red: 0x2B / 255.0, green: 0x4D / 255.0, blue: 0xE3 / 255.0)  // was #5071AD, brightened further
    // Darker version of greetingsBlue (60% brightness), for the outer border
    // ring around the big word's letters.
    static let greetingsBlueDark = Color(red: 0x1A / 255.0, green: 0x2E / 255.0, blue: 0x88 / 255.0)
    static let greetingsRed   = Color(red: 0xE3 / 255.0, green: 0x2B / 255.0, blue: 0x2B / 255.0)  // was #B83B3B, brightened further from #CD3131
    static let greetingsGold  = Color(red: 0xC7 / 255.0, green: 0x81 / 255.0, blue: 0x2B / 255.0)  // was #B8803B
    static let greetingsGreen = Color(red: 0x3B / 255.0, green: 0x92 / 255.0, blue: 0x48 / 255.0)  // was #42874C

    // Vivid orange for the rainbow stripe fill specifically — greetingsGold
    // is too muted/brownish to read as "orange" at rainbow-stripe scale.
    static let greetingsOrange = Color(red: 0xF2 / 255.0, green: 0x6A / 255.0, blue: 0x00 / 255.0)
}

// MARK: - Greetings Preset  (extrusion color scheme — independent of font choice)
//
// Temporarily built from the Burst feature's high-contrast primary palette
// (burstRed/burstYellow/burstBlue/burstGreen) instead of the muted custom
// tones, to make the extrusion/outline rendering easier to visually debug.

struct GreetingsPreset: Identifiable {
    let id: String
    let baseColor: Color    // top (front-facing) fill of the extruded word — also the swatch/fallback color when fillStripes is set
    let shadeColor: Color   // far (bottom) layer of the extrusion, and the drop-shadow tint
    let outlineColor: Color // outline stroke around the word
    let scriptColor: Color  // color of the "Greetings from" script line
    let badgeColor: Color   // background badge — keeps the badge legible over any photo
    var halftoneFill: Bool = false // vintage-print look: front face is a 45° dot screen instead of a solid fill
    var fillStripes: [Color]? = nil // when set, front face renders color bands (e.g. rainbow) clipped to the glyph outlines, instead of a solid baseColor fill
    var stripesVertical: Bool = false // band direction for fillStripes — false: bands stack left-to-right; true: bands stack bottom-to-top
    var gradientStripes: Bool = false // false: hard-edged bands; true: smoothly blended gradient across the same fillStripes colors

    // Vintage postcard "rainbow" band order, built from the existing
    // heritage palette rather than saturated primaries so it still reads as
    // part of the same color family as the other schemes.
    static let rainbowStripes: [Color] = [.greetingsRed, .greetingsOrange, .greetingsScriptYellow, .greetingsGreen, .greetingsBlue]

    // Display order (scheme IDs stay fixed for identification/persistence —
    // only this array's ordering, which drives the edit panel's swatch
    // order, has been rearranged).
    static let all: [GreetingsPreset] = [
        GreetingsPreset(id: "scheme6",
                         baseColor: .greetingsRed, shadeColor: .greetingsRed,
                         outlineColor: .white, scriptColor: .greetingsScriptYellow,
                         badgeColor: .brandBlue,
                         fillStripes: rainbowStripes, gradientStripes: true),
        GreetingsPreset(id: "scheme1",
                         baseColor: .greetingsRed, shadeColor: .greetingsRed,
                         outlineColor: .white, scriptColor: .greetingsScriptYellow,
                         badgeColor: .brandBlue,
                         fillStripes: rainbowStripes, stripesVertical: true),
        GreetingsPreset(id: "scheme5",
                         baseColor: .greetingsRed, shadeColor: .greetingsRed,
                         outlineColor: .white, scriptColor: .greetingsScriptYellow,
                         badgeColor: .brandBlue,
                         fillStripes: rainbowStripes, stripesVertical: true, gradientStripes: true),
        GreetingsPreset(id: "scheme3",
                         baseColor: .greetingsRed, shadeColor: .greetingsBlue,
                         outlineColor: .white, scriptColor: .greetingsScriptYellow,
                         badgeColor: .brandBlue),
        GreetingsPreset(id: "scheme4",
                         baseColor: .greetingsBlue, shadeColor: .greetingsRed,
                         outlineColor: .white, scriptColor: .greetingsScriptYellow,
                         badgeColor: .brandBlue),
    ]

    static func find(_ id: String) -> GreetingsPreset {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - Greetings Fixed Position  (replaces free drag/rotate with 3 presets)

enum GreetingsFixedPosition: String, CaseIterable {
    case center   // horizontal center, inset 20px from top, no rotation
    case left     // tilted, hugging the top-left while guaranteeing 0.5in
                  // clearance from the card's left/right edges — see center(...)

    var displayName: String {
        switch self {
        case .center: return "Center"
        case .left:   return "Tilt"
        }
    }

    func rotationDegrees(isLandscape: Bool) -> Double {
        guard self == .left else { return 0 }
        return -8
    }

    /// Center point to feed `.position()`, given the badge's own (pre-scale,
    /// pre-rotation) estimated size and the canvas it's rendered into.
    /// `.position()` and `.rotationEffect()` both reference the view's
    /// original, untransformed frame — so this works in that same space.
    /// The 20px inset is specified relative to the final 2700x1800 print
    /// resolution (see CardRenderer), so it's scaled here to whatever
    /// canvasSize is currently in play (small live-preview canvas or the
    /// actual print-resolution canvas at bake time).
    func center(badgeSize: CGSize, canvasSize: CGSize) -> CGPoint {
        let isLandscape = canvasSize.width >= canvasSize.height
        let referenceWidth: CGFloat = isLandscape ? 2775 : 1875
        let insetScale = canvasSize.width / referenceWidth
        let w = badgeSize.width, h = badgeSize.height
        switch self {
        case .center:
            // Fully bled to the top edge — no inset. Still horizontally centered.
            return CGPoint(x: canvasSize.width / 2, y: h / 2)
        case .left:
            let theta = rotationDegrees(isLandscape: isLandscape) * .pi / 180
            let cosT = CGFloat(cos(theta)), sinT = CGFloat(sin(theta))
            // Axis-aligned bounding box of the WxH badge once rotated by
            // theta about its own center — this is the real footprint we
            // need to keep clear of the card's left/right edges.
            let halfBBoxW = (abs(w * cosT) + abs(h * sinT)) / 2
            let halfBBoxH = (abs(w * sinT) + abs(h * cosT)) / 2
            // Guaranteed minimum clearance from the left/right edges — 0.5in
            // at 300dpi print scale (vs. letterEdgeClearance's 0.25in, which
            // only governs the un-rotated .center badge and the letters'
            // inset from their OWN badge edge, not the card edge).
            let clearance: CGFloat = 150 * insetScale
            let minCx = clearance + halfBBoxW
            let maxCx = canvasSize.width - clearance - halfBBoxW
            // Hug the left side of the valid range (preserves the original
            // "near the top-left corner" look) — but if the rotated badge is
            // too wide for both clearances to hold at once (an unusually
            // long word), fall back to dead-center rather than violating
            // either edge.
            let cx = minCx <= maxCx ? minCx : canvasSize.width / 2
            // Vertical placement: fixed so the ribbon's own visible TOP EDGE
            // (not its centerline) crosses the card's LEFT edge (x=0) at
            // exactly this many pixels down from the top, REGARDLESS of
            // word length/badge size — solved exactly from the top edge's
            // own parametric line equation (offset from the centerline by
            // h/2 in the rotated frame), so plugging any cx/h back in still
            // satisfies the crossing constraint exactly. Deliberately no
            // safety clamp here (an earlier max(halfBBoxH, ...) floor was
            // overriding this for wider badges, breaking the fixed-crossing
            // guarantee for longer words) — a sufficiently tall badge could
            // in principle extend above the canvas top, but a fixed,
            // word-length-independent crossing point is the explicit
            // requirement here.
            let leftEdgeCrossingY: CGFloat = 150 * insetScale  // 0.5in at 300dpi print scale
            let cy = leftEdgeCrossingY + cx * tan(theta) + (h / 2) / cos(theta)
            return CGPoint(x: cx, y: cy)
        }
    }
}

// MARK: - Greetings Safe Zone  (photo gesture-clamp boundary)

extension GreetingsOverlay {
    /// Bottom edge of the (first) badge's rendered footprint — rotated
    /// bounding box for Tilt, plain badge height for Center — as a fraction
    /// of canvas height (0 = top edge, 1 = bottom edge). Used to define the
    /// "safe zone" below which the front photo layer must always fully
    /// cover, regardless of zoom/pan, so an unintentional design error
    /// (photo zoomed out enough to leave a gap not hidden behind the
    /// banner) can't happen. Uses the same cheap estimate (not a real
    /// re-render) the live editor's own initial-placement fallback uses —
    /// good enough for a gesture-clamp boundary, doesn't need pixel-exact
    /// precision. Returns 0 (no safe zone) when there's no Greetings badge.
    static func safeZoneTopFraction(for overlays: [GreetingsOverlay], isLandscape: Bool) -> CGFloat {
        guard let overlay = overlays.first else { return 0 }
        let referenceWidth: CGFloat = isLandscape ? 2775 : 1875
        let referenceHeight: CGFloat = isLandscape ? 1875 : 2775
        let scriptFontSize = GreetingsGeometry.scriptFontSize(for: overlay.scriptText, isLandscape: isLandscape, scale: 1.0)
        let bigWordFontSize = GreetingsGeometry.bigWordFontSize(
            forLetterHeight: 225, maxBadgeWidth: referenceWidth - 2 * GreetingsBadgeRenderer.cardEdgeClearance,
            word: overlay.word, scriptText: overlay.scriptText, fontName: GreetingsGeometry.bigWordFontName, scriptFontSize: scriptFontSize,
            isLandscape: isLandscape, printScale: 1.0)
        let geometry = GreetingsGeometry(
            word: overlay.word, scriptText: overlay.scriptText, fontName: GreetingsGeometry.bigWordFontName, bigWordFontSize: bigWordFontSize,
            scriptFontSize: scriptFontSize, isLandscape: isLandscape, printScale: 1.0,
            isTilt: overlay.fixedPosition == .left)
        let badgeSize = geometry.estimatedBadgeSize()
        let canvasSize = CGSize(width: referenceWidth, height: referenceHeight)
        let center = overlay.fixedPosition.center(badgeSize: badgeSize, canvasSize: canvasSize)

        let bottomY: CGFloat
        if overlay.fixedPosition == .left {
            // Use the bottom-RIGHT corner's actual (rotated) Y specifically
            // — not the overall lowest point of the rotated bounding box
            // (which is the bottom-left corner, given this rotation
            // direction, and sits lower/stricter than necessary).
            let theta = overlay.fixedPosition.rotationDegrees(isLandscape: isLandscape) * .pi / 180
            let localX = badgeSize.width / 2
            let localY = badgeSize.height / 2
            let rotatedY = localX * sin(theta) + localY * cos(theta)
            bottomY = center.y + rotatedY
        } else {
            bottomY = center.y + badgeSize.height / 2
        }
        return min(1, max(0, bottomY / referenceHeight))
    }
}

// MARK: - Greetings Badge Background Color  (independent of the color
// scheme preset — chosen separately, shown as swatch dots next to the
// background-opacity slider)

enum GreetingsBadgeColor: String, CaseIterable, Identifiable {
    // .transparent listed first, then the same order as CanvasBackgroundColor's
    // swatches. GreetingsOverlay.badgeColorChoice's own default stays .blue —
    // adding this option here doesn't change what a new badge starts as.
    case transparent, white, black, blue, maroon, cream

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .transparent: return .clear
        case .blue:   return .brandBlue
        case .maroon: return Color(red: 0.85, green: 0.24, blue: 0.24)
        case .cream:  return Color(red: 0.85, green: 0.65, blue: 0.20)
        case .black:  return .black
        case .white:  return .white
        }
    }
}

// MARK: - Greetings Script (text) Color  (the "greetings from" script line's
// own color, independent of badgeColorChoice — shown as swatch dots next to
// the word input)

enum GreetingsScriptColor: String, CaseIterable, Identifiable {
    case yellow, white, black, red, blue

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .yellow: return .greetingsScriptYellow
        case .white:  return .white
        case .black:  return .black
        case .red:    return .greetingsRed
        // Same blue as the badge background's .blue choice — not the
        // separate, darker greetingsBlueDark.
        case .blue:   return .brandBlue
        }
    }

    // Fixed halo color for this script color — not user-choosable, only
    // on/off via GreetingsOverlay.haloEnabled.
    var haloColor: Color {
        switch self {
        case .yellow: return .black
        case .white:  return .black
        case .black:  return Color(white: 0.75)
        case .red:    return .black
        case .blue:   return .black
        }
    }
}

// MARK: - Greetings Overlay Model

struct GreetingsOverlay: Identifiable {
    var id: UUID = UUID()
    var word: String = ""
    // The script line above the big word — defaults to "greetings from" but
    // user-editable (see GreetingsCaptionEditPanel's Row 1 text field).
    // Rendered exactly as typed, letter case included; clearing it entirely
    // hides the script line (see GreetingsGeometry.displayScriptText).
    var scriptText: String = "greetings from"
    var presetID: String
    var fixedPosition: GreetingsFixedPosition = .left
    // Background badge opacity — slider-controlled, 0 (fully clear) to 1
    // (fully opaque), defaulting fully opaque.
    var backgroundOpacity: CGFloat = 1.0
    // Background badge color — independent of the presetID color scheme
    // (which has its own, now-unused, fixed `badgeColor: Color`). Defaults
    // to the CardDrop brand blue.
    var badgeColorChoice: GreetingsBadgeColor = .blue
    // "greetings from" script text color — defaults to yellow (selected)
    // rather than nil/auto so a swatch (and its halo) is always in effect
    // without requiring the user to tap one first.
    var scriptColorChoice: GreetingsScriptColor? = .yellow
    // Whether the fixed-color halo/border shows behind the script text —
    // independent of badgeColorChoice; the halo's own color is fixed per
    // scriptColorChoice (see GreetingsScriptColor.haloColor), not user-chosen.
    var haloEnabled: Bool = false

    init(presetID: String = GreetingsPreset.all[0].id) {
        self.presetID = presetID
    }
}

// MARK: - Greetings Geometry  (fixed big-word font size — no shrink-to-fit;
// the badge grows to whatever width the content actually needs)

struct GreetingsGeometry {
    static let scriptFontName = "DancingScript-Bold"
    static let bigWordFontName = "BowlbyOneSC-Regular"

    let displayWord: String
    let wordCount: Int    // raw overlay.word.count (before the "Home" empty-word fallback) — used to gate bigWordPull
    let scriptFontSize:  CGFloat
    let bigWordFontSize: CGFloat
    let isLandscape: Bool        // pull (script-to-bigword overlap) differs by orientation
    let isTilt: Bool             // Tilt gets a taller bottom margin than Center — see estimatedBadgeSize()
    let printScale: CGFloat      // canvas-units-per-print-pixel — needed so the fixed-print-pixel `margin` in estimatedBadgeSize() matches GreetingsCaptionView's real render exactly
    let bigWordWidth: CGFloat    // raw measured width of the big word at bigWordFontSize
    let scriptText: String       // the full on-canvas script string (with its leading double-nbsp lead-in), e.g. "  greetings from" — see displayScriptText(_:)
    let scriptTextWidth: CGFloat // raw measured width of scriptText at scriptFontSize — the script line's own true width, NOT contentWidth (which is usually dominated by the much-wider big word)
    let contentWidth: CGFloat    // max(script line width, big word's own padded canvas width) — the width the badge/script frame need to fully enclose both

    // Double-nbsp lead-in kept in front of the script text — purely a visual
    // left-indent, independent of what the user typed.
    static let scriptPrefix = "\u{00A0}\u{00A0}"

    // The user-editable script line (GreetingsOverlay.scriptText, default
    // "greetings from") is rendered exactly as typed — including genuinely
    // blank (hides the script line entirely) if the user clears the field.
    static func displayScriptText(_ rawScriptText: String) -> String {
        let trimmed = rawScriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : scriptPrefix + trimmed
    }

    // Used ONLY to solve the script line's font size / vertical layout
    // metrics (never for what's actually drawn) — falls back to the default
    // phrase when blank so the badge's height/spacing stays stable rather
    // than trying to divide by a zero-width measurement. See
    // scriptFontSize(for:isLandscape:scale:).
    private static func metricsScriptText(_ rawScriptText: String) -> String {
        let trimmed = rawScriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        return scriptPrefix + (trimmed.isEmpty ? "greetings from" : trimmed)
    }

    init(word: String, scriptText rawScriptText: String, fontName: String, bigWordFontSize: CGFloat, scriptFontSize: CGFloat, isLandscape: Bool, printScale: CGFloat, isTilt: Bool = false) {
        let effectiveWord = word.isEmpty ? "Home" : word.uppercased()
        displayWord = effectiveWord
        wordCount = word.count
        self.bigWordFontSize = bigWordFontSize
        self.scriptFontSize = scriptFontSize
        self.isLandscape = isLandscape
        self.isTilt = isTilt
        self.printScale = printScale
        self.scriptText = GreetingsGeometry.displayScriptText(rawScriptText)

        let w = BurstGeometry.measureText(effectiveWord, fontName: fontName, size: bigWordFontSize)
        bigWordWidth = w

        // Mirrors ExtrudedBigWordText's own internal padding so the "big
        // word" side of the comparison matches its true rendered footprint.
        let outlineWidth = max(0.825, bigWordFontSize * 0.0198)
        let shadowOffsetX = bigWordFontSize * 0.05
        let shadowOffsetY = bigWordFontSize * 0.15
        let bigWordPad = max(shadowOffsetX, shadowOffsetY) + outlineWidth + outlineWidth * 4 / 3 + 4
        let bigWordCanvasWidth = w + bigWordPad * 2

        scriptTextWidth = BurstGeometry.measureText(self.scriptText, fontName: GreetingsGeometry.scriptFontName, size: scriptFontSize)

        contentWidth = max(bigWordCanvasWidth, scriptTextWidth)
    }

    // "greetings from" is rendered at a fixed on-card WIDTH — 1200px
    // (print-resolution) in landscape, 800px in portrait — rather than
    // scaling off the big word's font size, so it reads at a consistent
    // size across every card regardless of the greeting word's length.
    // Text width is linear in font size for a fixed string, so this solves
    // directly from one reference measurement rather than iterating.
    static func scriptFontSize(for rawScriptText: String, isLandscape: Bool, scale: CGFloat) -> CGFloat {
        let targetWidth = (isLandscape ? 1000 : 800) * scale
        let referenceSize: CGFloat = 100
        let referenceWidth = BurstGeometry.measureText(metricsScriptText(rawScriptText), fontName: scriptFontName, size: referenceSize)
        guard referenceWidth > 0 else { return targetWidth }
        return targetWidth * referenceSize / referenceWidth
    }

    // Analytical estimate of the whole badge's rendered size, used only to
    // compute the 3 fixed-position center points (GreetingsFixedPosition).
    // Mirrors the padding/sizing math in GreetingsCaptionView/
    // ExtrudedBigWordText — an approximation, not the true rendered size, so
    // keep these ratios in sync if those views' constants change.
    func estimatedBadgeSize() -> CGSize {
        let badgeHPad = bigWordFontSize * 0.06
        // Fixed print-scale top/bottom margins — must match GreetingsCaptionView's
        // topMargin/bottomMargin constants exactly (their sum is what matters
        // here, since only the total height is used below), or this estimate
        // (used to place the badge with zero top inset for .center)
        // under/overestimates the real height and crops the badge against
        // the canvas edge.
        let topMargin = (isTilt ? 70 : (isLandscape ? 90 : 80)) * printScale
        let bottomMargin = (isTilt ? -40 : -40) * printScale
        // Two independent pulls — script line pulled down toward the big
        // word, big word pulled up toward the script line — must match
        // GreetingsCaptionView's ratios exactly. Proportional to
        // bigWordFontSize (not scriptFontSize) so the gap stays consistent
        // regardless of word length.
        let bigWordPull = bigWordFontSize * (wordCount <= 5 ? 0.0 : 0.1)
        let scriptPull = bigWordFontSize * (isLandscape ? 0.2 : 0.2)

        let scriptFont = UIFont(name: GreetingsGeometry.scriptFontName, size: scriptFontSize)
        let scriptLayoutHeight = scriptFont.map { $0.ascender - $0.descender } ?? scriptFontSize

        let bigFont = UIFont(name: GreetingsGeometry.bigWordFontName, size: bigWordFontSize * 1.1) ?? UIFont.boldSystemFont(ofSize: bigWordFontSize * 1.1)
        let arcHeight = bigWordFontSize * 0.40
        // The big word's own reserved extrusion/outline pad (see GreetingsCaptionView's
        // .padding(.top, 0) / .padding(.bottom, ...)) is mostly absorbed/hidden by the
        // offset(-bigWordPull)/.padding(-bigWordPull) overlap with the
        // script line above it — empirically it does not add anywhere near
        // its raw reserved amount to the badge's real visible height, so
        // it's left out here rather than counted in full (counting it in
        // full overestimates height and pushes .center's zero-inset
        // placement down, leaving a gap at the canvas top).
        let bigWordHeight = (bigFont.ascender - bigFont.descender) + arcHeight

        // Empirical correction — the analytical formula above still doesn't
        // fully capture how the offset()/negative-padding pull tricks
        // interact with layout, and screenshots showed the estimate running
        // long (a visible gap between .center's zero-inset
        // placement and the canvas top edge). Tune this value directly
        // against screenshots rather than re-deriving the formula.
        let heightFudge: CGFloat = (isLandscape ? 75 : 50) * printScale

        let width = badgeHPad * 2 + contentWidth
        let height = topMargin + max(0, scriptLayoutHeight - scriptPull) + max(0, bigWordHeight - bigWordPull) + bottomMargin - heightFudge
        return CGSize(width: width, height: height)
    }

    // Given a desired height for the big word's LETTERS themselves (cap
    // height — not the ascender-descender line box, and not the script
    // line, extrusion depth, arc lift, or padding around it), finds the
    // bigWordFontSize that produces it. Cap height is exactly linear in
    // point size for a given font, so this solves directly from one
    // reference measurement rather than iterating.
    static func bigWordFontSize(forLetterHeight desiredHeight: CGFloat) -> CGFloat {
        guard desiredHeight > 0 else { return 8 }
        let referenceSize: CGFloat = 100
        let referenceFont = UIFont(name: GreetingsGeometry.bigWordFontName, size: referenceSize) ?? UIFont.boldSystemFont(ofSize: referenceSize)
        let referenceCapHeight = referenceFont.capHeight
        guard referenceCapHeight > 0 else { return desiredHeight }
        return desiredHeight * referenceSize / referenceCapHeight
    }

    // Same as above, but also caps the badge WIDTH at maxBadgeWidth (the
    // full card width) — a long word shrinks the font size until it fits
    // rather than overflowing the card. Badge width isn't perfectly linear
    // in font size (fixed padding terms), so this takes a few correction
    // passes to converge.
    static func bigWordFontSize(forLetterHeight desiredHeight: CGFloat, maxBadgeWidth: CGFloat, word: String, scriptText: String, fontName: String, scriptFontSize: CGFloat, isLandscape: Bool, printScale: CGFloat) -> CGFloat {
        var fontSize = bigWordFontSize(forLetterHeight: desiredHeight)
        guard maxBadgeWidth > 0 else { return fontSize }
        for _ in 0..<4 {
            let g = GreetingsGeometry(word: word, scriptText: scriptText, fontName: fontName, bigWordFontSize: fontSize, scriptFontSize: scriptFontSize, isLandscape: isLandscape, printScale: printScale)
            let badgeWidth = g.estimatedBadgeSize().width
            guard badgeWidth > maxBadgeWidth else { break }
            fontSize *= maxBadgeWidth / badgeWidth
        }
        return max(8, fontSize)
    }
}
