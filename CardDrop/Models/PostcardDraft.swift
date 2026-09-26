import SwiftUI
import Combine

enum PostcardOrientation {
    case landscape  // 6x4
    case portrait   // 4x6

    var aspectRatio: CGFloat {
        switch self {
        case .landscape: return 6.0 / 4.0  // 1.5
        case .portrait:  return 4.0 / 6.0  // 0.667
        }
    }
}

enum PostcardBorder: String {
    case fullBleed
    case whiteBorder
    case customText
    case decorative
}

// Fill color for any part of the canvas the photo doesn't cover (moved/
// resized to leave a gap) — solid, no opacity control. Same 5 colors, same
// order, as the Greetings badge background (see GreetingsBadgeColor) —
// blue/maroon/cream delegate directly to that enum's own color values so
// the two pickers can never drift apart; white/black are just literal
// here since GreetingsBadgeColor already defines its own identical ones.
enum CanvasBackgroundColor: String, CaseIterable, Identifiable, Codable {
    // Default — lets the back photo layer (see PostcardDraft.rendered(at:))
    // show through any gap instead of a flat color.
    case transparent
    case white, black, blue, maroon, cream

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .transparent: return .clear
        case .white:  return .white
        case .black:  return .black
        case .blue:   return GreetingsBadgeColor.blue.color
        case .maroon: return GreetingsBadgeColor.maroon.color
        case .cream:  return GreetingsBadgeColor.cream.color
        }
    }
}

// Cardback message font choice — PRINT (AmericanTypewriter) or SCRIPT
// (DancingScript-Bold). The two fonts need different (fontSize, lineHeight)
// tuning per canvas, and on the 6x9 back a different message-polygon/band
// geometry too (a script font's letterforms need more vertical room, which
// nudges where the branding band sits) — see each canvas's own per-style
// constants, keyed off this enum, rather than a single shared value.
enum CardbackMessageFont: String, CaseIterable, Identifiable, Codable, Hashable {
    case print
    case script

    var id: String { rawValue }

    var uiFontName: String {
        switch self {
        case .print:  return "AmericanTypewriter"
        case .script: return "DancingScript-Bold"
        }
    }
}

enum ModerationState {
    case untested   // not yet checked, or content changed since last check
    case passed     // checked and clean — skip re-check until content changes
}

class PostcardDraft: ObservableObject {
    /// Stable identity for this card. Generated once at draft creation,
    /// persisted in the snapshot, used as the Supabase storage key.
    /// Never changes — sending is immutable, edits require a duplicate.
    var cardID: UUID = UUID()

    @Published var image: UIImage? {
        didSet { imageModeratedState = .untested }
    }
    @Published var composedImage: UIImage? {
        didSet { imageModeratedState = .untested }
    }
    @Published var orientation: PostcardOrientation = .landscape
    @Published var imageScale: CGFloat = 1.0
    @Published var imageOffset: CGSize = .zero
    @Published var filter: PostcardFilter = .none
    @Published var border: PostcardBorder = .fullBleed
    @Published var canvasBackgroundColor: CanvasBackgroundColor = .transparent
    // Whether the photo gap above the front layer shows a vertically-
    // flipped reflection of the front layer's own top edge, or just the
    // plain independently-scaled back layer with no mirroring. Only really
    // visible/relevant with a Tilt Greetings badge, which is why its toggle
    // lives in that edit panel rather than a general Style It control.
    @Published var photoMirrorEnabled: Bool = true
    @Published var borderText: String = ""
    @Published var borderFontName: String = "Georgia"
    @Published var borderTextColor: Color = .black
    @Published var decorativePresetID: String = ""
    @Published var textOverlays: [TextOverlay] = []
    @Published var burstOverlays: [BurstCaptionOverlay] = []
    @Published var greetingsOverlays: [GreetingsOverlay] = []
    @Published var qrOverlays: [QROverlay] = [] {
        didSet { moderationState = .untested }
    }

    // Transient — not persisted. Not @Published (no view observes it directly).
    var moderationState: ModerationState = .untested
    var imageModeratedState: ModerationState = .untested

    // Transient — not persisted. Write Card's To/From nicknames are
    // required to move forward (but not backward); these flip true on a
    // blocked forward-navigation attempt — from either the step's own Next
    // button or the wizard's forward chevron — and clear as soon as the
    // corresponding field is edited. @Published since MessageStepView's
    // fields observe them directly to draw a red outline.
    @Published var showRecipientNicknameError = false
    @Published var showSenderNicknameError = false

    // Casual nicknames, entered in the first flow step
    @Published var senderNickname: String = ""
    @Published var recipientNickname: String = ""

    // Back side
    @Published var message: String = "" {
        didSet { moderationState = .untested }
    }
    @Published var messageFont: CardbackMessageFont = .print

    // Digital-only cardback ink-free-zone content: an optional greeting
    // combo (salutation + closing) and an optional standalone phrase.
    // The *Salutation/Closing/Text fields hold the resolved (placeholder-
    // filled) display text — PostcardBackCanvas reads those directly rather
    // than re-fetching zz_cardback_greetings/zz_cardback_phrases itself.
    @Published var greetingId: UUID?
    @Published var greetingSalutation: String = ""
    @Published var greetingClosing: String = ""
    @Published var phraseCategory: String = "All"
    @Published var phraseId: UUID?
    @Published var phraseText: String = ""
    @Published var senderFirstName: String = ""
    @Published var senderLastName: String = ""
    @Published var senderStreet: String = ""
    @Published var senderCity: String = ""
    @Published var senderState: String = ""
    @Published var senderZip: String = ""
    @Published var senderCountry: String = ""
    @Published var recipientFirstName: String = ""
    @Published var recipientLastName: String = ""
    @Published var recipientStreet: String = ""
    @Published var recipientCity: String = ""
    @Published var recipientState: String = ""
    @Published var recipientZip: String = ""
    @Published var recipientCountry: String = ""

    var senderName: String { [senderFirstName, senderLastName].filter { !$0.isEmpty }.joined(separator: " ") }
    var recipientName: String { [recipientFirstName, recipientLastName].filter { !$0.isEmpty }.joined(separator: " ") }

    var formattedSenderAddress: String {
        Self.formatAddress(street: senderStreet, city: senderCity, state: senderState, zip: senderZip, country: senderCountry)
    }
    var formattedRecipientAddress: String {
        Self.formatAddress(street: recipientStreet, city: recipientCity, state: recipientState, zip: recipientZip, country: recipientCountry)
    }
    static func formatAddress(street: String, city: String, state: String, zip: String, country: String) -> String {
        var lines: [String] = []
        if !street.isEmpty { lines.append(street) }
        let cityStateZip = [city, [state, zip].filter { !$0.isEmpty }.joined(separator: "  ")]
            .filter { !$0.isEmpty }.joined(separator: ", ")
        if !cityStateZip.isEmpty { lines.append(cityStateZip) }
        if !country.isEmpty { lines.append(country) }
        return lines.joined(separator: "\n")
    }
    @Published var senderEmail: String = ""
    @Published var senderPhone: String = ""
    @Published var recipientEmail: String = ""
    @Published var recipientPhone: String = ""

    @Published var includeQRCode: Bool = true
    @Published var qrCodeContent: String = ""
    @Published var includeBackMessageQR: Bool = false {
        didSet { moderationState = .untested }
    }
    @Published var backMessageQRContent: String = "" {
        didSet { moderationState = .untested }
    }

    /// Returns a new unsent draft with all content copied and recipient fields cleared.
    /// The clone gets a fresh cardID so it is independent of the original.
    func cloneForNewRecipient() -> PostcardDraft {
        let c = PostcardDraft()
        // cardID is a fresh UUID() from PostcardDraft()
        c.image              = image
        c.composedImage      = composedImage
        c.orientation        = orientation
        c.imageScale         = imageScale
        c.imageOffset        = imageOffset
        c.filter             = filter
        c.border             = border
        c.canvasBackgroundColor = canvasBackgroundColor
        c.photoMirrorEnabled = photoMirrorEnabled
        c.borderText         = borderText
        c.borderFontName     = borderFontName
        c.borderTextColor    = borderTextColor
        c.decorativePresetID = decorativePresetID
        c.textOverlays       = textOverlays
        c.burstOverlays      = burstOverlays
        c.greetingsOverlays  = greetingsOverlays
        c.qrOverlays         = qrOverlays
        c.senderNickname     = senderNickname
        c.message            = message
        c.messageFont        = messageFont
        // Greeting text is recipient-specific (uses recipientNickname, which
        // is intentionally left blank below), so only the selection carries
        // over — MessageStepView recomputes greetingSalutation/Closing once
        // a new recipientNickname is entered. Phrase text has no such
        // dependency and copies straight across.
        c.greetingId         = greetingId
        c.phraseCategory     = phraseCategory
        c.phraseId           = phraseId
        c.phraseText         = phraseText
        c.senderFirstName    = senderFirstName
        c.senderLastName     = senderLastName
        c.senderStreet       = senderStreet
        c.senderCity         = senderCity
        c.senderState        = senderState
        c.senderZip          = senderZip
        c.senderCountry      = senderCountry
        c.senderEmail        = senderEmail
        c.senderPhone        = senderPhone
        c.includeQRCode      = includeQRCode
        c.qrCodeContent      = qrCodeContent
        c.includeBackMessageQR  = includeBackMessageQR
        c.backMessageQRContent  = backMessageQRContent
        // Formal recipient name/address/email/phone are intentionally left
        // blank — a copy is likely headed to a different/uncertain recipient.
        // The "To" nickname carries over though, since it's just the card's
        // starting text and the common case is re-sending the same card.
        c.recipientNickname  = recipientNickname
        return c
    }

    /// Returns a new unsent draft that's a precise replica of a sent card —
    /// every field copied, including the "To" nickname, greeting text, and
    /// whatever recipient contact info (formal name/address/email/phone) was
    /// captured via the contact picker. Used for "Copy & Edit" on an already-
    /// sent card, where the point is to reopen exactly what was sent (in
    /// Style It) rather than start over with a blank recipient — unlike
    /// cloneForNewRecipient(), which is for actually sending to someone new.
    /// The clone still gets a fresh cardID so it's independent of the original.
    func cloneExact() -> PostcardDraft {
        let c = cloneForNewRecipient()
        c.greetingSalutation   = greetingSalutation
        c.greetingClosing      = greetingClosing
        c.recipientFirstName   = recipientFirstName
        c.recipientLastName    = recipientLastName
        c.recipientStreet      = recipientStreet
        c.recipientCity        = recipientCity
        c.recipientState       = recipientState
        c.recipientZip         = recipientZip
        c.recipientCountry     = recipientCountry
        c.recipientEmail       = recipientEmail
        c.recipientPhone       = recipientPhone
        return c
    }

    /// Renders the positioned/scaled photo into a UIImage at the postcard aspect ratio.
    func renderComposedImage(frameSize: CGSize) {
        composedImage = rendered(at: frameSize)
    }

    private func rendered(at size: CGSize) -> UIImage? {
        guard let image else { return nil }

        let imageSize = image.size
        let fillScale = max(size.width / imageSize.width, size.height / imageSize.height)
        let totalScale = fillScale * imageScale

        let scaledWidth = imageSize.width * totalScale
        let scaledHeight = imageSize.height * totalScale

        // imageOffset is stored NORMALIZED (fraction of canvas width/height
        // dragged), not raw points — it has to be, since it's set from a
        // small live-editor-canvas DragGesture but consumed here at
        // whatever `size` this is being baked at (the live editor's own
        // small canvas for the live preview, or the full 2700x1800 print
        // canvas for the composedImage bake). Raw, unnormalized points
        // captured at editor scale would end up a negligible fraction of a
        // canvas ~8x larger. See TextOverlayStepView's matching drag/live
        // display code for the other half of this convention.
        let drawRect = CGRect(
            x: (size.width - scaledWidth) / 2 + imageOffset.width * size.width,
            y: (size.height - scaledHeight) / 2 + imageOffset.height * size.height,
            width: scaledWidth,
            height: scaledHeight
        )

        // Back layer: same photo, floored at "just covers the canvas"
        // (imageScale never below 1.0 here, even if the front layer is
        // zoomed out further than that) — zooms in together with the front
        // layer past that floor. Guarantees every corner of the canvas
        // always shows real photo content instead of the plain backdrop
        // color, regardless of how the front layer is panned/zoomed — e.g.
        // so a tilted Greetings badge's top-left corner is never left
        // empty. X position is locked to the front layer's own horizontal
        // pan (moves in unison) so wherever the back layer peeks through,
        // it's horizontally aligned with the front layer's content — Y
        // stays fixed/centered regardless of vertical pan, since that's
        // what guarantees top/bottom coverage under the banner.
        let backScale = fillScale * max(1.0, imageScale)
        let backWidth = imageSize.width * backScale
        let backHeight = imageSize.height * backScale
        let backDrawRect = CGRect(
            x: (size.width - backWidth) / 2 + imageOffset.width * size.width,
            y: (size.height - backHeight) / 2,
            width: backWidth,
            height: backHeight
        )

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            ctx.cgContext.clip(to: CGRect(origin: .zero, size: size))
            // Back photo layer first (always covers, per backDrawRect above)
            // — a solid canvasBackgroundColor, when chosen, then paints OVER
            // it (e.g. to deliberately fill the tilt corner with a flat
            // color instead of showing the back photo there). Default is
            // .transparent, leaving the back photo visible as before; if
            // this is ever an unexpected empty state with no photo at all,
            // white/black/etc. still guarantee a solid JPEG (no alpha).
            image.draw(in: backDrawRect)
            // Mirror layer (user-toggleable — see photoMirrorEnabled): a
            // vertically-flipped duplicate of the front layer's own
            // content, reflected around the front layer's own top edge
            // (drawRect.minY) — continues the photo as a seamless
            // reflection into the gap above, instead of the back layer's
            // independently-cropped (different part of the photo) view.
            // Matches TextOverlayStepView's live-editor mirror layer exactly.
            if photoMirrorEnabled {
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: 0, y: 2 * drawRect.minY)
                ctx.cgContext.scaleBy(x: 1, y: -1)
                image.draw(in: drawRect)
                ctx.cgContext.restoreGState()
            }
            if canvasBackgroundColor != .transparent {
                UIColor(canvasBackgroundColor.color).setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
            image.draw(in: drawRect)
        }
    }
}
