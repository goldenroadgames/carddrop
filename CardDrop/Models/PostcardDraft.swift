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

    // Digital-only cardback ink-free-zone content: an optional greeting
    // combo (salutation + closing) and an optional standalone phrase.
    // The *Salutation/Closing/Text fields hold the resolved (placeholder-
    // filled) display text — PostcardBackCanvas reads those directly rather
    // than re-fetching cardback_greetings/cardback_phrases itself.
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

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            ctx.cgContext.clip(to: CGRect(origin: .zero, size: size))
            // Fill a backdrop color first — if the drag/zoom leaves the photo
            // not fully covering `size` (e.g. dragged/positioned such that an
            // edge is exposed), that gap must render as something solid in
            // the saved output, not transparent/undefined (JPEG has no
            // alpha, so an unfilled gap would otherwise composite
            // unpredictably). Opaque white by default; if a Greetings badge
            // is present, match its own badge background color instead, so
            // an exposed gap reads as an intentional matching color rather
            // than a jarring mismatch against the badge.
            let backdropColor: UIColor = greetingsOverlays.first.map { UIColor($0.badgeColorChoice.color) } ?? .white
            backdropColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: drawRect)
        }
    }
}
