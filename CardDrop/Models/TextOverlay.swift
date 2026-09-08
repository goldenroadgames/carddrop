import SwiftUI
import UIKit

// MARK: - QR Overlay (secret message on front)

struct QROverlay: Identifiable {
    var id: UUID = UUID()
    /// The raw text the user typed. Empty = no user input yet.
    var userInputText: String = ""
    /// The actual text encoded in the QR. Defaults to the promo tagline until the user types something.
    var content: String = QROverlay.defaultContent
    var normalizedPosition: CGPoint = CGPoint(x: 0.25, y: 0.75)

    /// Fixed size: ~0.75" on a 6x4 physical card (0.75/4 ≈ 0.19 of short dimension)
    static let fixedNormalizedSize: CGFloat = 0.19

    static let defaultContent = "CardDrop - the OG Personal Messenger"

    /// Snaps normalizedPosition to the nearest corner given the canvas size, with padding.
    mutating func snapToNearestCorner(canvasSize: CGSize) {
        let size = QROverlay.fixedNormalizedSize * min(canvasSize.width, canvasSize.height)
        let pad: CGFloat = 8
        let halfSize = size / 2
        let margin = (halfSize + pad) / canvasSize.width
        let marginV = (halfSize + pad) / canvasSize.height

        let corners: [CGPoint] = [
            CGPoint(x: margin,       y: marginV),
            CGPoint(x: 1 - margin,   y: marginV),
            CGPoint(x: margin,       y: 1 - marginV),
            CGPoint(x: 1 - margin,   y: 1 - marginV),
        ]
        let nearest = corners.min(by: {
            hypot($0.x - normalizedPosition.x, $0.y - normalizedPosition.y) <
            hypot($1.x - normalizedPosition.x, $1.y - normalizedPosition.y)
        }) ?? corners[3]
        normalizedPosition = nearest
    }

    /// Flips horizontal between left and right corners, preserving top/bottom.
    mutating func flipHorizontal(canvasSize: CGSize) {
        let size = QROverlay.fixedNormalizedSize * min(canvasSize.width, canvasSize.height)
        let margin = (size / 2 + 4) / canvasSize.width
        normalizedPosition.x = normalizedPosition.x < 0.5 ? 1 - margin : margin
    }

    /// Flips vertical between top and bottom corners, preserving left/right.
    mutating func flipVertical(canvasSize: CGSize) {
        let size = QROverlay.fixedNormalizedSize * min(canvasSize.width, canvasSize.height)
        let marginV = (size / 2 + 4) / canvasSize.height
        normalizedPosition.y = normalizedPosition.y < 0.5 ? 1 - marginV : marginV
    }
}

// MARK: - Background Style

enum TextBgStyle: String, CaseIterable {
    case none    = "None"
    case box     = "Box"
    case speech  = "Speech"
    case thought = "Thought"

    var systemImage: String {
        switch self {
        case .none:    return "square.slash"
        case .box:     return "rectangle"
        case .speech:  return "message.fill"
        case .thought: return "cloud.fill"
        }
    }
}

// MARK: - Tail horizontal position

// Two stops (left / right) that the H tail-position button in the edit
// panel cycles through in an endless loop on each tap. Each is positioned
// 25% of the bubble's CURRENT width in from its respective edge (see
// SpeechBubbleShape/ThoughtBubbleShape) — proportional to width rather than
// a fixed pixel offset, so the tail stays correctly attached as the bubble
// is resized wider via the Width slider.
enum TailHPosition: Int, CaseIterable {
    case left, right

    var next: TailHPosition {
        TailHPosition(rawValue: (rawValue + 1) % TailHPosition.allCases.count) ?? .left
    }
}

// MARK: - Model

struct TextOverlay: Identifiable {
    let id: UUID
    var text: String
    var normalizedPosition: CGPoint   // 0–1 relative to canvas width/height
    var normalizedWidth: CGFloat      // 0–1 relative to canvas width
    var fontName: String
    var fontSize: CGFloat             // absolute pt size at the time of creation (at canvasWidth)
    var canvasWidth: CGFloat          // canvas width when fontSize was set; used for proportional scaling
    var textColor: Color
    var bgStyle: TextBgStyle
    var bgColor: Color
    var tailHPosition: TailHPosition = .left  // left/right — cycled by the edit panel button
    var tailFlippedV: Bool            // mirror tail top↔bottom (speech only)

    static let availableFonts: [(name: String, displayName: String)] = [
        ("Georgia",            "Georgia"),
        ("HelveticaNeue",      "Helvetica"),
        ("Futura-Medium",      "Futura"),
        ("AmericanTypewriter", "Typewriter"),
    ]

    var rotation: Double = 0            // degrees
    var isBold:   Bool   = false
    var isItalic: Bool   = false

    /// Returns the PostScript font name that matches the requested bold/italic traits.
    static func resolvedFontName(base: String, bold: Bool, italic: Bool) -> String {
        switch base {
        case "Georgia":
            if bold && italic { return "Georgia-BoldItalic" }
            if bold           { return "Georgia-Bold" }
            if italic         { return "Georgia-Italic" }
        case "HelveticaNeue":
            if bold && italic { return "HelveticaNeue-BoldItalic" }
            if bold           { return "HelveticaNeue-Bold" }
            if italic         { return "HelveticaNeue-Italic" }
        case "AmericanTypewriter":
            if bold           { return "AmericanTypewriter-Bold" }
        case "Futura-Medium":
            if bold && italic { return "Futura-BoldOblique" }
            if bold           { return "Futura-Bold" }
            if italic         { return "Futura-MediumItalic" }
        default:
            return TextOverlay.resolvedFontName(base: "HelveticaNeue", bold: bold, italic: italic)
        }
        return base
    }

    var resolvedFontName: String {
        TextOverlay.resolvedFontName(base: fontName, bold: isBold, italic: isItalic)
    }

    init(at position: CGPoint = CGPoint(x: 0.5, y: 0.5), canvasWidth: CGFloat = 0) {
        id                 = UUID()
        text               = ""
        normalizedPosition = position
        normalizedWidth    = 0.5
        fontName           = "Georgia"
        fontSize           = 12
        self.canvasWidth   = canvasWidth
        textColor          = .black
        bgStyle            = .box
        bgColor            = .white
        tailFlippedV       = false
        rotation           = 0
        isBold             = false
        isItalic           = false
    }
}

// MARK: - Shared bubble content (used by both the live editor and the print bake)
//
// Building the Text+padding+background composition ONCE here and reusing it
// in both the live editor (TextOverlayItemView) and the print bake
// (PostcardFrontCanvas) — rather than each independently re-deriving the
// same formula at two different absolute point sizes — is what guarantees
// the two can never drift apart: the exact same CoreText layout pass runs
// in both places (same literal font-size number), just displayed at
// different final scales by the caller (the editor wraps this in a
// .scaleEffect to shrink it back down to on-screen size; the bake doesn't
// need to, since ImageRenderer captures it at its native size). Text
// line-wrapping is NOT perfectly scale-invariant across very different
// absolute point sizes (font hinting/grid-fitting rounds glyph widths more
// at small sizes) — two independent Text layouts at e.g. 18pt vs 79pt can
// wrap differently even at an identical proportional width, which is
// exactly the bug this sidesteps.
struct TextOverlayBubbleView: View {
    let overlay: TextOverlay
    // Multiplies every absolute-pt constant below (font size, padding, tail
    // height, corner radius, outline width) — pass 1 for "editor-native"
    // sizing, or (targetCanvasWidth / overlay.canvasWidth) to lay out at
    // print scale.
    let scale: CGFloat
    // Already-scaled absolute width, i.e. overlay.normalizedWidth * the
    // same reference canvas width `scale` was computed against.
    let boxWidth: CGFloat

    // Capped at 36 (the edit panel's slider max) regardless of what's
    // stored on the overlay — a safety net for any pre-existing overlay
    // saved before this cap existed. CoreText line-wrapping gets unreliable
    // at very large absolute point sizes (scaledFontSize can otherwise run
    // well past 100-150pt once `scale` — the editor-to-print multiplier,
    // often 6-9x — is applied), which read as wrapping just silently
    // stopping above some threshold.
    private var scaledFontSize: CGFloat { min(overlay.fontSize, 36) * scale }

    // SwiftUI's Font.custom(name:size:) doesn't reliably size custom fonts
    // when rendered through ImageRenderer (the print bake) — it comes out a
    // different size than the identical request rendered live in the editor,
    // even though the point size passed in is provably identical (confirmed
    // via debug instrumentation: same scaledFontSize in both, only the
    // ImageRenderer-rendered text came out wrong). Resolving a concrete
    // UIFont ourselves and wrapping it sidesteps whatever SwiftUI/ImageRenderer
    // does differently with the by-name font descriptor lookup.
    private var textFont: Font {
        if let uiFont = UIFont(name: overlay.resolvedFontName, size: scaledFontSize) {
            return Font(uiFont)
        }
        return .system(size: scaledFontSize)
    }

    private var topPad: CGFloat {
        if overlay.bgStyle == .speech  && overlay.tailFlippedV { return SpeechBubbleShape.tailHeight(scale: scale) }
        if overlay.bgStyle == .thought && overlay.tailFlippedV { return ThoughtBubbleShape.tailHeight(scale: scale) }
        return 0
    }
    private var botPad: CGFloat {
        if overlay.bgStyle == .speech  && !overlay.tailFlippedV { return SpeechBubbleShape.tailHeight(scale: scale) }
        if overlay.bgStyle == .thought && !overlay.tailFlippedV { return ThoughtBubbleShape.tailHeight(scale: scale) }
        return 0
    }
    // The thought bubble's scalloped cloud edge dips inward of its bounding
    // box between bumps, so text needs extra clearance beyond the plain
    // box/speech-bubble padding to stay clear of the outline.
    private var cloudExtraHPadding: CGFloat { (overlay.bgStyle == .thought ? 2 : 0) * scale }
    private var cloudExtraVPadding: CGFloat { (overlay.bgStyle == .thought ? 2 : 0) * scale }
    private var basePadH: CGFloat {
        switch overlay.bgStyle {
        case .thought:       return 2 * scale
        case .box, .speech:  return 12 * scale
        case .none:          return 5 * scale
        }
    }
    private var basePadV: CGFloat {
        switch overlay.bgStyle {
        case .thought:       return 2 * scale
        case .box, .speech:  return 12 * scale
        case .none:          return 4 * scale
        }
    }

    var body: some View {
        // Modifier order matters: .frame(width:) applied directly to the raw
        // Text BEFORE padding/background, not after — an outer .frame
        // wrapping padding+background proposes a narrower width down to
        // Text than this does for the mathematically "same" normalizedWidth,
        // causing an earlier/different wrap point.
        Text(overlay.text.isEmpty ? " " : overlay.text)
            .font(textFont)
            .foregroundColor(overlay.textColor)
            .multilineTextAlignment(overlay.bgStyle == .none ? .leading : .center)
            .frame(width: boxWidth, alignment: overlay.bgStyle == .none ? .leading : .center)
            // Keeps width authoritative (wrapping still happens at
            // boxWidth) but forces height to Text's true intrinsic
            // (multi-line) height regardless of what an ambient ancestor
            // proposes. Needed because this view is often laid out at a
            // much larger print-equivalent scale inside a container sized
            // to the small on-screen editor canvas (see TextOverlayItemView,
            // which shrinks the result back down via .scaleEffect AFTER
            // this lays out) — Text treats an insufficient height proposal
            // as a cue to truncate rather than overflow, so without this it
            // silently truncates to a single line once the true wrapped
            // height exceeds that small ambient proposal.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, basePadH + cloudExtraHPadding)
            .padding(.top,    basePadV + cloudExtraVPadding + topPad)
            .padding(.bottom, basePadV + cloudExtraVPadding + botPad)
            .background(bgShape)
    }

    @ViewBuilder
    private var bgShape: some View {
        switch overlay.bgStyle {
        case .none:
            Color.clear
        case .box:
            RoundedRectangle(cornerRadius: 30 * scale)
                .fill(overlay.bgColor)
                .overlay(RoundedRectangle(cornerRadius: 30 * scale).stroke(Color.black, lineWidth: 2 * scale))
        case .speech:
            // Body and tail are two subpaths that only overlap slightly at
            // their join, so a plain .stroke() draws a seam there. Inflate +
            // fill-behind (black copy slightly larger, drawn behind the
            // normal-size colored copy, both filled never stroked) instead.
            ZStack {
                SpeechBubbleShape(tailPosition: overlay.tailHPosition, tailOnBottom: !overlay.tailFlippedV, inflate: 2, scale: scale)
                    .fill(Color.black)
                SpeechBubbleShape(tailPosition: overlay.tailHPosition, tailOnBottom: !overlay.tailFlippedV, scale: scale)
                    .fill(overlay.bgColor)
            }
        case .thought:
            // Same inflate/fill-behind reasoning as .speech above — a plain
            // .stroke() on the cloud would draw each circle's full boundary,
            // including lines cutting through the interior union.
            // No left/right tail control for thought bubbles — always dead
            // center — but up/down still selects top vs bottom.
            ZStack {
                ThoughtBubbleShape(tailOnBottom: !overlay.tailFlippedV, inflate: 2, scale: scale)
                    .fill(Color.black)
                ThoughtBubbleShape(tailOnBottom: !overlay.tailFlippedV, scale: scale)
                    .fill(overlay.bgColor)
            }
        }
    }
}

// MARK: - Speech Bubble Shape
//
// The shape fills the entire rect. The bubble occupies all but `tailHeight` points
// on the tail side; the triangle protrudes into that reserved space.
// tailPosition – left/center/right placement of the triangle along the base
// tailOnBottom – tail hangs below the bubble (false = tail points upward)

struct SpeechBubbleShape: Shape {
    var tailPosition: TailHPosition = .left
    var tailOnBottom: Bool = true
    // When > 0, grows both the rounded-rect body and the triangle tail —
    // used the same way as ThoughtBubbleShape's `inflate`: draw an inflated
    // black copy behind the normal (inflate: 0) colored copy, both filled
    // (never stroked), so overlaps never show a seam. See that shape's
    // comment for why plain .stroke() doesn't work here. Expressed in
    // editor-native points — scaled by `scale` internally like everything else.
    var inflate: CGFloat = 0
    // Editor-canvas-native size -> print-resolution-canvas size multiplier
    // (same role as PostcardFrontCanvas's `fontScale`) — EVERY absolute-pt
    // constant in this shape must be multiplied by `scale`, or the tail/
    // corner-radius/outline proportions drift between the small live editor
    // preview and the ~2700px print bake (they used to be literal points,
    // fine-looking in the small editor canvas but proportionally tiny
    // against the huge print canvas). Defaults to 1 (editor-native).
    var scale: CGFloat = 1
    private static let baseTailHeight: CGFloat = 28  // 2x
    static func tailHeight(scale: CGFloat) -> CGFloat { baseTailHeight * scale }

    func path(in rect: CGRect) -> Path {
        let tailH = Self.tailHeight(scale: scale)
        let infl = inflate * scale
        let bubbleRect: CGRect
        if tailOnBottom {
            bubbleRect = CGRect(x: rect.minX, y: rect.minY,
                                width: rect.width, height: rect.height - tailH)
        } else {
            bubbleRect = CGRect(x: rect.minX, y: rect.minY + tailH,
                                width: rect.width, height: rect.height - tailH)
        }

        var path = Path(roundedRect: bubbleRect.insetBy(dx: -infl, dy: -infl), cornerRadius: 30 * scale + infl)

        // Base of the triangle is widened and pulled `overlap` points INTO
        // the bubble body (rather than sitting exactly on its edge) so the
        // two subpaths genuinely intersect instead of merely touching —
        // required for the inflate/fill-behind outline trick to work
        // seamlessly at the join.
        let baseWidth: CGFloat = 28 * scale  // widened to match the now-longer (2x) tail
        let overlap: CGFloat = 8 * scale
        let baseX: CGFloat
        let apexX: CGFloat
        // Anchored 25% of the bubble's CURRENT width in from the respective
        // edge — proportional, not a fixed pixel offset, so the tail stays
        // correctly attached to the body as the bubble is resized wider.
        let baseCenterX: CGFloat
        switch tailPosition {
        case .left:  baseCenterX = bubbleRect.minX + bubbleRect.width * 0.25
        case .right: baseCenterX = bubbleRect.maxX - bubbleRect.width * 0.25
        }
        baseX = baseCenterX - baseWidth / 2
        apexX = baseCenterX

        if tailOnBottom {
            path.move(to:    CGPoint(x: baseX - infl,             y: bubbleRect.maxY - overlap))
            path.addLine(to: CGPoint(x: baseX + baseWidth + infl, y: bubbleRect.maxY - overlap))
            path.addLine(to: CGPoint(x: apexX,                    y: rect.maxY + infl))
        } else {
            // Base points deliberately listed in the OPPOSITE order from the
            // tailOnBottom case (right corner first, then left) — Path fills
            // use the non-zero winding rule, and simply flipping the apex
            // from below to above (without also reversing the base order)
            // flips this triangle's winding relative to the rounded-rect
            // body's. Where they overlap, opposite windings cancel to a
            // hole instead of reinforcing into a solid union — this read as
            // a see-through notch cut into the bubble. Reversing the base
            // order here keeps the winding matched.
            path.move(to:    CGPoint(x: baseX + baseWidth + infl, y: bubbleRect.minY + overlap))
            path.addLine(to: CGPoint(x: baseX - infl,             y: bubbleRect.minY + overlap))
            path.addLine(to: CGPoint(x: apexX,                    y: rect.minY - infl))
        }
        path.closeSubpath()

        return path
    }
}

// MARK: - Thought Bubble Shape
//
// No left/right tail control — always dead center. Up/down still controls
// whether the tail comes from the top or bottom. No tilt on the tail line
// itself (not even the cloud body's own -8° whole-cloud tilt; the tail
// hangs true-vertical in the image's own coordinate frame regardless of how
// the cloud above it is tilted).
// tailOnBottom – tail hangs below the cloud (false = above)

struct ThoughtBubbleShape: Shape {
    var tailOnBottom: Bool = true
    // When > 0, every circle making up the cloud (body + tail dots) is
    // grown by this many points around its own center. Drawing an
    // `inflate`d black copy of this same shape BEHIND the normal (inflate:
    // 0) colored copy — both filled, never stroked — produces a clean rim
    // outline around the true outer silhouette with no interior seams,
    // since .fill() never draws lines at internal overlaps the way
    // .stroke() does (stroking each circle's full boundary would draw
    // visible lines cutting through the union's interior).
    var inflate: CGFloat = 0
    // Same role/rationale as SpeechBubbleShape.scale — see that shape's
    // comment. Note: the cloud BODY (cloudBody below) already self-scales
    // proportionally to whatever bubbleRect it's given (aspect-fill from a
    // fixed design size), so it needs no extra scaling here — only the tail
    // dots and `inflate`, which are literal editor-native point offsets,
    // need multiplying by `scale`.
    var scale: CGFloat = 1
    private static let baseTailHeight: CGFloat = 80  // grown to fit 5 dots at 2x size
    static func tailHeight(scale: CGFloat) -> CGFloat { baseTailHeight * scale }

    func path(in rect: CGRect) -> Path {
        let tailH = Self.tailHeight(scale: scale)
        let infl = inflate * scale
        let bubbleRect: CGRect
        if tailOnBottom {
            bubbleRect = CGRect(x: rect.minX, y: rect.minY,
                                width: rect.width, height: rect.height - tailH)
        } else {
            bubbleRect = CGRect(x: rect.minX, y: rect.minY + tailH,
                                width: rect.width, height: rect.height - tailH)
        }
        var path = Self.cloudBody(in: bubbleRect, inflate: infl)

        // The dot chain anchors to the CLOUD's own actual rendered extent
        // (cloudRect — the aspect-filled bounding box, which commonly
        // overflows past bubbleRect on one axis; see cloudRect(for:)), not
        // to bubbleRect itself. bubbleRect is just whatever shape the text
        // box happens to be; the cloud silhouette rarely lines up with its
        // edges exactly, so anchoring to bubbleRect could leave the tail
        // floating away from the cloud, or buried inside it, depending on
        // how the text box's aspect ratio compares to the cloud's design
        // ratio. Anchoring to the cloud's real edge keeps the tail visually
        // attached regardless of the text box's shape.
        let cloud = Self.cloudRect(for: bubbleRect)

        // Nudged slightly left of dead center (not perfectly centered — a
        // tad off looks more natural) — no left/right control, no tilt
        // (not even the cloud body's own -8° whole-cloud tilt; this hangs
        // true-vertical in the image's own frame). Built as a perfectly
        // straight vertical line running from the anchor point toward
        // whichever side the tail is on.
        let anchorX = cloud.midX - cloud.width * 0.05
        // Pulled in from the cloud's edge by the largest dot's own radius
        // (20pt diameter / 2 = 10pt), same "pull the join point INTO the
        // body" idea used elsewhere (see SpeechBubbleShape's `overlap`) —
        // keeps the chain visually connected to the cloud instead of
        // starting right at its outer boundary.
        let largestDotRadius: CGFloat = 10 * scale
        let anchorY = tailOnBottom ? cloud.maxY - largestDotRadius : cloud.minY + largestDotRadius

        func dot(dy: CGFloat, size: CGFloat) -> CGRect {
            let sz = size * scale
            let center = CGPoint(x: anchorX, y: anchorY + dy * scale)
            return CGRect(x: center.x - sz / 2, y: center.y - sz / 2, width: sz, height: sz)
                .insetBy(dx: -infl, dy: -infl)
        }

        // 4 dots — largest closest to the cloud, tapering down/up as they
        // trail away (the 5th/smallest/farthest dot was imperceptible and
        // got dropped). Gaps between dots scale with the dots themselves
        // (doubling radius without doubling the gap between centers is
        // what caused them to overlap earlier).
        let sizes: [CGFloat] = [20, 14, 8, 6]
        let dyBottom: [CGFloat] = [1, 25, 43, 57]
        let dyTop: [CGFloat] = [-1, -25, -43, -57]

        for i in 0..<sizes.count {
            path.addEllipse(in: dot(dy: tailOnBottom ? dyBottom[i] : dyTop[i], size: sizes[i]))
        }

        return path
    }

    // Puffy-cloud silhouette: 5 ellipses traced from a reference 5-circle
    // cloud arrangement, laid out once in a fixed "design space" and scaled
    // as ONE rigid unit into bubbleRect (aspect-fill — a single uniform
    // scale factor for both axes, never independent x/y stretching). This
    // is why resizing the overlay grows/moves all 5 shapes in lockstep
    // instead of them drifting apart — same effect as scaling one embedded
    // image. Every adjacent pair's center distance is deliberately kept
    // well under the sum of their radii so there's real overlap (not just a
    // near-touch) — an earlier version had a gap in the middle because two
    // of the traced shapes didn't actually overlap.
    // Whole-cloud tilt applied in cloudBody below — shared so the tail dot
    // chain (path(in:)) can correct its own anchor position/angle to match.
    private static let cloudTiltDegrees: CGFloat = -8
    private static let cloudDesignSize = CGSize(width: 605, height: 380)
    // Numbered clockwise from top (2=top-right, 5=left), matching how the
    // user references them. 1 (top), 3 (bottom-right), 4 (bottom-center)
    // all removed — down to 2 ellipses total.
    private static let cloudDesignEllipses: [(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, rotationDeg: CGFloat)] = [
        (350, 198.66, 236.25, 166.36, 10),  // 2: top-right — wide/flat, +10°, nudged down (ry +25%, +25% again; rx -10%)
        (150, 185, 155,   143,   0),  // 5: left (ry +25%, +10%)
    ]

    // The cloud's actual rendered bounding box — bubbleRect aspect-FILLED
    // (scaled by whichever axis needs more scale so the cloud always fully
    // covers bubbleRect, then centered), so this commonly overflows past
    // bubbleRect on one axis. This is the box the tail dot chain anchors to
    // (see path(in:)), not bubbleRect itself.
    private static func cloudRect(for bubbleRect: CGRect) -> CGRect {
        let scale = max(bubbleRect.width / cloudDesignSize.width,
                         bubbleRect.height / cloudDesignSize.height)
        let scaledSize = CGSize(width: cloudDesignSize.width * scale, height: cloudDesignSize.height * scale)
        let offsetX = bubbleRect.minX + (bubbleRect.width  - scaledSize.width)  / 2
        let offsetY = bubbleRect.minY + (bubbleRect.height - scaledSize.height) / 2
        return CGRect(origin: CGPoint(x: offsetX, y: offsetY), size: scaledSize)
    }

    private static func cloudBody(in bubbleRect: CGRect, inflate: CGFloat = 0) -> Path {
        var path = Path()

        // Aspect-fill: scale by whichever axis needs MORE scale so the
        // traced cloud always fully covers bubbleRect (text never pokes
        // outside it) — the tradeoff is slight overflow past bubbleRect on
        // the other axis, which is fine for a background shape.
        let cloud = cloudRect(for: bubbleRect)
        let scale = cloud.width / cloudDesignSize.width
        let offsetX = cloud.minX
        let offsetY = cloud.minY

        for e in cloudDesignEllipses {
            let rx = e.rx * scale + inflate
            let ry = e.ry * scale + inflate
            let cx = offsetX + e.cx * scale
            let cy = offsetY + e.cy * scale
            // Built centered at the origin, in its own local space, so
            // rotating around its own center is a plain rotate — then
            // translated out to (cx, cy).
            var ellipse = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
            var t = CGAffineTransform.identity
            t = t.translatedBy(x: cx, y: cy)
            t = t.rotated(by: e.rotationDeg * .pi / 180)
            ellipse = ellipse.applying(t)
            path.addPath(ellipse)
        }

        // Whole-cloud tilt — rotate the already-composed path (not each
        // ellipse individually) around bubbleRect's own center so the
        // 5-shape arrangement rotates as one rigid unit.
        let pivot = CGPoint(x: bubbleRect.midX, y: bubbleRect.midY)
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: pivot.x, y: pivot.y)
        transform = transform.rotated(by: cloudTiltDegrees * .pi / 180)
        transform = transform.translatedBy(x: -pivot.x, y: -pivot.y)
        path = path.applying(transform)

        return path
    }
}
