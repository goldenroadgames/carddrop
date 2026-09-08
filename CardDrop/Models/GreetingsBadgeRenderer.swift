import SwiftUI

// MARK: - Greetings Badge Renderer
//
// The editor's live preview and the print bake used to each independently
// re-run the SAME analytical layout formulas (GreetingsCaptionView /
// ExtrudedBigWordText) at two wildly different `printScale` values (a small
// fraction for the live-preview canvas, 1.0 for the full 2700x1800/1800x2700
// print resolution). Any non-linear term in that formula — a fixed pixel
// literal, a `max(...)` floor — behaves differently in proportion at those
// two scales, so the two renders could drift apart no matter how carefully
// the formula was tuned against one of them.
//
// Instead, the badge is rendered to a bitmap exactly ONCE, at the canonical
// print resolution (printScale = 1.0). Both the live editor and the print
// bake then just display THAT SAME bitmap — the editor scales it down to
// fit its small canvas, the print bake uses it at native size (or scaled to
// fit an inset/bordered print area) — so they can never diverge: they are
// the same pixels, just resized, not two independent re-derivations of the
// same formula.
@MainActor
enum GreetingsBadgeRenderer {
    /// Renders the badge at the canonical print resolution for the given
    /// orientation (2700x1800 landscape / 1800x2700 portrait, printScale =
    /// 1.0). Returns the rendered bitmap and its exact size (in points,
    /// with `renderer.scale = 1` so 1 point == 1 print pixel) — this exact
    /// size should be used for fixed-position placement instead of
    /// `GreetingsGeometry.estimatedBadgeSize()`'s approximation.
    // Minimum clearance the big word's own letters must keep from the
    // card's left/right edges — 1/4in at 300dpi.
    static let letterEdgeClearance: CGFloat = 75

    static func render(overlay: GreetingsOverlay, isLandscape: Bool) -> (image: UIImage, size: CGSize)? {
        let referenceWidth: CGFloat = isLandscape ? 2775 : 1875
        let preset = GreetingsPreset.find(overlay.presetID)
        let scriptFontSize = GreetingsGeometry.scriptFontSize(isLandscape: isLandscape, scale: 1.0)
        let targetHeight: CGFloat = 225  // 1in at 300dpi, printScale = 1.0
        // Reserve letterEdgeClearance on the far side so even a long word
        // (whose badge width gets capped/shrunk to fit) leaves that much
        // room between the badge's own edge and the card edge — combined
        // with extraHorizontalPad (the letters' own inset from the badge
        // edge) below, this guarantees the letters themselves never land
        // closer than letterEdgeClearance to the card's left/right edges.
        let bigWordFontSize = GreetingsGeometry.bigWordFontSize(
            forLetterHeight: targetHeight, maxBadgeWidth: referenceWidth - letterEdgeClearance, word: overlay.word,
            fontName: GreetingsGeometry.bigWordFontName, scriptFontSize: scriptFontSize,
            isLandscape: isLandscape, printScale: 1.0)
        // +75 bleed-margin match — see GreetingsCaptionView's identical fix.
        let tiltMinWidth: CGFloat = isLandscape ? 2925 : 2000

        // Landscape tilt reads better with the text left-justified a fixed
        // distance from the widened backgroundMinWidth box's left edge,
        // rather than centered. Portrait keeps dead-center.
        let tiltLeadingInset: CGFloat = 160

        // .center/.corner get letterEdgeClearance (1/4in at 300dpi) of
        // padding per side between the letters and the badge's own edge —
        // for .corner (flush to the card's left edge, zero inset), this is
        // the ONLY thing standing between the letters and the card edge, so
        // it must equal the full clearance, not just widen the badge a bit.
        // .left/tilt is unaffected: it already sizes itself via
        // backgroundMinWidth.
        let extraHorizontalPad: CGFloat = overlay.fixedPosition == .left ? 0 : letterEdgeClearance

        // "greetings from" script color — the user's explicit swatch pick,
        // or the current scheme's own default (preset.scriptColor, except
        // dark blue for contrast against the harvest-gold .cream badge)
        // when they haven't chosen one. Picking a new color scheme resets
        // scriptColorChoice to nil (see GreetingsCaptionEditPanel), so this
        // default re-takes effect until the user overrides it again.
        let schemeDefaultScriptColor: Color = overlay.badgeColorChoice == .cream ? .greetingsBlueDark : preset.scriptColor
        let scriptColorOverride: Color? = overlay.scriptColorChoice?.color ?? schemeDefaultScriptColor

        // Rendered WITHOUT the background rectangle (transparent) — the
        // caller draws that separately, live, so backgroundOpacity can be
        // dragged/animated without invalidating this cached bitmap at all.
        let view = GreetingsCaptionView(
            word: overlay.word, preset: preset, bigWordFontSize: bigWordFontSize,
            scriptFontSize: scriptFontSize, isLandscape: isLandscape, printScale: 1.0,
            scriptColorOverride: scriptColorOverride,
            drawsBackground: false,
            backgroundMinWidth: overlay.fixedPosition == .left ? tiltMinWidth : nil,
            contentLeadingInset: overlay.fixedPosition == .left && isLandscape ? tiltLeadingInset : nil,
            extraHorizontalPad: extraHorizontalPad)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.uiImage else { return nil }
        return (image, image.size)
    }
}
