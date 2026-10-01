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
    // Minimum clearance the letters' own badge box keeps from its
    // (unrotated) edge — 1/4in at 300dpi. Purely cosmetic inset around the
    // letters; NOT what guarantees card-edge clearance (see cardEdgeClearance).
    static let letterEdgeClearance: CGFloat = 75

    // Guaranteed minimum clearance from the CARD's own left/right edges —
    // 0.5in at 300dpi. Applies to both .center (via the maxBadgeWidth cap
    // below, since a centered badge's clearance is exactly (canvasWidth -
    // badgeWidth)/2) and .left/Tilt (via the rotated-bounding-box math in
    // GreetingsFixedPosition.center()) — must match the literal `150` used
    // there.
    static let cardEdgeClearance: CGFloat = 150

    static func render(overlay: GreetingsOverlay, isLandscape: Bool) -> (image: UIImage, size: CGSize)? {
        let referenceWidth: CGFloat = isLandscape ? 2775 : 1875
        let preset = GreetingsPreset.find(overlay.presetID)
        let scriptFontSize = GreetingsGeometry.scriptFontSize(for: overlay.scriptText, isLandscape: isLandscape, scale: 1.0)
        let targetHeight: CGFloat = 225  // 1in at 300dpi, printScale = 1.0
        // Cap the badge's own (unrotated) width so that, once centered
        // (.center) or rotated-and-placed (.left/Tilt, per its own math),
        // the letters never land closer than cardEdgeClearance to the
        // card's left/right edges — a long word shrinks its font rather
        // than overflowing that guarantee.
        let bigWordFontSize = GreetingsGeometry.bigWordFontSize(
            forLetterHeight: targetHeight, maxBadgeWidth: referenceWidth - 2 * cardEdgeClearance, word: overlay.word,
            scriptText: overlay.scriptText, fontName: GreetingsGeometry.bigWordFontName, scriptFontSize: scriptFontSize,
            isLandscape: isLandscape, printScale: 1.0)

        // letterEdgeClearance (1/4in at 300dpi) of padding per side between
        // the letters and the badge's own (un-rotated) edge — for Tilt, the
        // real guarantee against the CARD's edges comes from the rotated-
        // bounding-box clearance math in GreetingsFixedPosition.center(...)
        // instead; this is just the letters' inset from their own badge box.
        let extraHorizontalPad: CGFloat = letterEdgeClearance

        // "greetings from" script color — the user's explicit swatch pick,
        // or the current scheme's own default (preset.scriptColor, except
        // dark blue for contrast against the harvest-gold .cream badge)
        // when they haven't chosen one. Picking a new color scheme resets
        // scriptColorChoice to nil (see GreetingsCaptionEditPanel), so this
        // default re-takes effect until the user overrides it again.
        let schemeDefaultScriptColor: Color = overlay.badgeColorChoice == .cream ? .greetingsBlueDark : preset.scriptColor
        let scriptColorOverride: Color? = overlay.scriptColorChoice?.color ?? schemeDefaultScriptColor

        // Halo's color is fixed per scriptColorChoice (see
        // GreetingsScriptColor.haloColor), independent of badgeColorChoice —
        // only shows when the user has explicitly picked one of the 5 script
        // swatches (there's no defined halo for the unpicked scheme-default
        // color) AND the Halo toggle is on.
        let scriptBorderColor: Color = overlay.haloEnabled ? (overlay.scriptColorChoice?.haloColor ?? .clear) : .clear

        // Rendered WITHOUT the background rectangle (transparent) — the
        // caller draws that separately, live, so backgroundOpacity can be
        // dragged/animated without invalidating this cached bitmap at all.
        let view = GreetingsCaptionView(
            word: overlay.word, rawScriptText: overlay.scriptText, preset: preset, bigWordFontSize: bigWordFontSize,
            scriptFontSize: scriptFontSize, isLandscape: isLandscape, printScale: 1.0,
            scriptColorOverride: scriptColorOverride,
            drawsBackground: false,
            extraHorizontalPad: extraHorizontalPad,
            isTilt: overlay.fixedPosition.isTilt,
            scriptBorderColor: scriptBorderColor)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.uiImage else { return nil }
        return (image, image.size)
    }
}
