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
    case left     // top-left corner, tilted -12°, so the badge's top-right and
                  // bottom-left corners each sit 20px from the top/left edges
    case corner   // top-left corner, inset 20px top/left, no rotation

    var displayName: String {
        switch self {
        case .center: return "Center"
        case .corner: return "Corner"
        case .left:   return "Tilt"
        }
    }

    var rotationDegrees: Double { self == .left ? -8 : 0 }

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
        let inset: CGFloat = 20 * insetScale
        let w = badgeSize.width, h = badgeSize.height
        switch self {
        case .corner:
            // Fully bled to the top-left edge — no inset.
            return CGPoint(x: w / 2, y: h / 2)
        case .center:
            // Fully bled to the top edge — no inset. Still horizontally centered.
            return CGPoint(x: canvasSize.width / 2, y: h / 2)
        case .left:
            let theta = rotationDegrees * .pi / 180
            let cosT = CGFloat(cos(theta)), sinT = CGFloat(sin(theta))
            // Solve for the center such that the rotated top-right corner
            // sits at y = inset and the rotated bottom-left corner sits at
            // x = inset (two constraints, two unknowns).
            let cx = inset + (w / 2) * cosT + (h / 2) * sinT
            let cy = inset - (w / 2) * sinT + (h / 2) * cosT
            // Nudge up/left from that solved position (print scale).
            let nudgeUp: CGFloat = 150 * insetScale
            let nudgeLeft: CGFloat = 50 * insetScale
            // Landscape only: lift another 1/2in (150px at 300dpi print
            // scale) on top of the nudge above.
            let landscapeExtraNudgeUp: CGFloat = isLandscape ? 150 * insetScale : 0
            return CGPoint(x: cx - nudgeLeft, y: cy - nudgeUp - landscapeExtraNudgeUp)
        }
    }
}

// MARK: - Greetings Badge Background Color  (independent of the color
// scheme preset — chosen separately, shown as swatch dots next to the
// background-opacity slider)

enum GreetingsBadgeColor: String, CaseIterable, Identifiable {
    case blue, maroon, cream

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue:   return .brandBlue
        case .maroon: return Color(red: 0.85, green: 0.24, blue: 0.24)
        case .cream:  return Color(red: 0.85, green: 0.65, blue: 0.20)
        }
    }
}

// MARK: - Greetings Script (text) Color  (the "greetings from" script line's
// own color, independent of badgeColorChoice — shown as swatch dots next to
// the word input)

enum GreetingsScriptColor: String, CaseIterable, Identifiable {
    case yellow, black, blue, red, white

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .yellow: return .greetingsScriptYellow
        case .black:  return .black
        case .blue:   return .greetingsBlueDark
        case .red:    return .greetingsRed
        case .white:  return .white
        }
    }
}

// MARK: - Greetings Overlay Model

struct GreetingsOverlay: Identifiable {
    var id: UUID = UUID()
    var word: String = ""
    var presetID: String
    var fixedPosition: GreetingsFixedPosition = .center
    // Background badge opacity — slider-controlled, 0 (fully clear) to 1
    // (fully opaque), defaulting fully opaque.
    var backgroundOpacity: CGFloat = 1.0
    // Background badge color — independent of the presetID color scheme
    // (which has its own, now-unused, fixed `badgeColor: Color`). Defaults
    // to the CardDrop brand blue.
    var badgeColorChoice: GreetingsBadgeColor = .blue
    // "greetings from" script text color. nil = auto, tracking
    // badgeColorChoice.defaultScriptColor as the badge color changes — once
    // the user taps a swatch, this is set explicitly and stops tracking.
    var scriptColorChoice: GreetingsScriptColor? = nil

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
    let scriptFontSize:  CGFloat
    let bigWordFontSize: CGFloat
    let isLandscape: Bool        // pull (script-to-bigword overlap) differs by orientation
    let printScale: CGFloat      // canvas-units-per-print-pixel — needed so the fixed-print-pixel `margin` in estimatedBadgeSize() matches GreetingsCaptionView's real render exactly
    let bigWordWidth: CGFloat    // raw measured width of the big word at bigWordFontSize
    let scriptTextWidth: CGFloat // raw measured width of "greetings from" at scriptFontSize — the script line's own true width, NOT contentWidth (which is usually dominated by the much-wider big word)
    let contentWidth: CGFloat    // max(script line width, big word's own padded canvas width) — the width the badge/script frame need to fully enclose both

    // "greetings from" is the literal on-canvas string (with its leading
    // double-nbsp lead-in) that scriptFontSize is solved against — kept here
    // so the solver and the actual rendered text can never drift apart.
    static let scriptText = "\u{00A0}\u{00A0}greetings from"

    init(word: String, fontName: String, bigWordFontSize: CGFloat, scriptFontSize: CGFloat, isLandscape: Bool, printScale: CGFloat) {
        let effectiveWord = word.isEmpty ? "Home" : word.uppercased()
        displayWord = effectiveWord
        self.bigWordFontSize = bigWordFontSize
        self.scriptFontSize = scriptFontSize
        self.isLandscape = isLandscape
        self.printScale = printScale

        let w = BurstGeometry.measureText(effectiveWord, fontName: fontName, size: bigWordFontSize)
        bigWordWidth = w

        // Mirrors ExtrudedBigWordText's own internal padding so the "big
        // word" side of the comparison matches its true rendered footprint.
        let outlineWidth = max(0.825, bigWordFontSize * 0.0198)
        let shadowOffsetX = bigWordFontSize * 0.05
        let shadowOffsetY = bigWordFontSize * 0.15
        let bigWordPad = max(shadowOffsetX, shadowOffsetY) + outlineWidth + outlineWidth * 4 / 3 + 4
        let bigWordCanvasWidth = w + bigWordPad * 2

        scriptTextWidth = BurstGeometry.measureText(GreetingsGeometry.scriptText, fontName: GreetingsGeometry.scriptFontName, size: scriptFontSize)

        contentWidth = max(bigWordCanvasWidth, scriptTextWidth)
    }

    // "greetings from" is rendered at a fixed on-card WIDTH — 1200px
    // (print-resolution) in landscape, 800px in portrait — rather than
    // scaling off the big word's font size, so it reads at a consistent
    // size across every card regardless of the greeting word's length.
    // Text width is linear in font size for a fixed string, so this solves
    // directly from one reference measurement rather than iterating.
    static func scriptFontSize(isLandscape: Bool, scale: CGFloat) -> CGFloat {
        let targetWidth = (isLandscape ? 1000 : 800) * scale
        let referenceSize: CGFloat = 100
        let referenceWidth = BurstGeometry.measureText(scriptText, fontName: scriptFontName, size: referenceSize)
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
        // Flat 37.5px (print scale) margin, top and bottom — must match the
        // `margin` constant in GreetingsCaptionView exactly, or this estimate
        // (used to place the badge with zero top inset for .center/.corner)
        // under/overestimates the real height and crops the badge against
        // the canvas edge.
        let margin = 37.5 * printScale
        // Two independent pulls — script line pulled down toward the big
        // word, big word pulled up toward the script line — must match
        // GreetingsCaptionView's ratios exactly.
        let bigWordPull = scriptFontSize * (isLandscape ? 0.3 : 0.3)
        let scriptPull = scriptFontSize * (isLandscape ? 0.35 : 0.35)

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
        // full overestimates height and pushes .center/.corner's zero-inset
        // placement down, leaving a gap at the canvas top).
        let bigWordHeight = (bigFont.ascender - bigFont.descender) + arcHeight

        // Empirical correction — the analytical formula above still doesn't
        // fully capture how the offset()/negative-padding pull tricks
        // interact with layout, and screenshots showed the estimate running
        // long (a visible gap between .center/.corner's zero-inset
        // placement and the canvas top edge). Tune this value directly
        // against screenshots rather than re-deriving the formula.
        let heightFudge: CGFloat = (isLandscape ? 75 : 50) * printScale

        let width = badgeHPad * 2 + contentWidth
        let height = margin + max(0, scriptLayoutHeight - scriptPull) + max(0, bigWordHeight - bigWordPull) + margin - heightFudge
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
    static func bigWordFontSize(forLetterHeight desiredHeight: CGFloat, maxBadgeWidth: CGFloat, word: String, fontName: String, scriptFontSize: CGFloat, isLandscape: Bool, printScale: CGFloat) -> CGFloat {
        var fontSize = bigWordFontSize(forLetterHeight: desiredHeight)
        guard maxBadgeWidth > 0 else { return fontSize }
        for _ in 0..<4 {
            let g = GreetingsGeometry(word: word, fontName: fontName, bigWordFontSize: fontSize, scriptFontSize: scriptFontSize, isLandscape: isLandscape, printScale: printScale)
            let badgeWidth = g.estimatedBadgeSize().width
            guard badgeWidth > maxBadgeWidth else { break }
            fontSize *= maxBadgeWidth / badgeWidth
        }
        return max(8, fontSize)
    }
}
