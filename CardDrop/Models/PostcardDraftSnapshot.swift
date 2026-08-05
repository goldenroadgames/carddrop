import SwiftUI

// MARK: - QR overlay snapshot

struct QROverlaySnapshot: Codable {
    var id: UUID
    var content: String
    var userInputText: String
    var posX, posY: Double

    init(_ overlay: QROverlay) {
        id             = overlay.id
        content        = overlay.content
        userInputText  = overlay.userInputText
        posX           = overlay.normalizedPosition.x
        posY           = overlay.normalizedPosition.y
    }

    var toQROverlay: QROverlay {
        var o = QROverlay()
        o.id                 = id
        o.content            = content
        o.userInputText      = userInputText
        o.normalizedPosition = CGPoint(x: posX, y: posY)
        return o
    }
}

// MARK: - Text overlay snapshot (Codable substitute for TextOverlay)

struct TextOverlaySnapshot: Codable {
    var id: UUID
    var text: String
    var posX, posY: Double
    var normalizedWidth: Double
    var fontName: String
    var fontSize: Double
    var canvasWidth: Double            // 0 = legacy draft; scale skipped on restore
    var textR, textG, textB, textA: Double
    var bgStyleRaw: String
    var bgR, bgG, bgB, bgA: Double
    var tailFlippedH: Bool
    var tailFlippedV: Bool
    var rotation: Double
    var isBold:   Bool
    var isItalic: Bool

    init(_ overlay: TextOverlay) {
        id            = overlay.id
        text          = overlay.text
        posX          = overlay.normalizedPosition.x
        posY          = overlay.normalizedPosition.y
        normalizedWidth = Double(overlay.normalizedWidth)
        fontName      = overlay.fontName
        fontSize      = Double(overlay.fontSize)
        canvasWidth   = Double(overlay.canvasWidth)
        bgStyleRaw    = overlay.bgStyle.rawValue
        tailFlippedH  = overlay.tailFlippedH
        tailFlippedV  = overlay.tailFlippedV
        rotation      = overlay.rotation
        isBold        = overlay.isBold
        isItalic      = overlay.isItalic

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(overlay.textColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        textR = Double(r); textG = Double(g); textB = Double(b); textA = Double(a)

        UIColor(overlay.bgColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        bgR = Double(r); bgG = Double(g); bgB = Double(b); bgA = Double(a)
    }

    var toTextOverlay: TextOverlay {
        var o = TextOverlay(at: CGPoint(x: posX, y: posY))
        o.text             = text
        o.normalizedWidth  = CGFloat(normalizedWidth)
        o.fontName         = fontName
        o.fontSize         = CGFloat(fontSize)
        o.canvasWidth      = CGFloat(canvasWidth)
        o.textColor        = Color(red: textR, green: textG, blue: textB, opacity: textA)
        o.bgStyle          = TextBgStyle(rawValue: bgStyleRaw) ?? .none
        o.bgColor          = Color(red: bgR, green: bgG, blue: bgB, opacity: bgA)
        o.tailFlippedH     = tailFlippedH
        o.tailFlippedV     = tailFlippedV
        o.rotation         = rotation
        o.isBold           = isBold
        o.isItalic         = isItalic
        return o
    }
}

// MARK: - Burst caption overlay snapshot

struct BurstCaptionOverlaySnapshot: Codable {
    var id: UUID
    var text: String
    var presetID: String
    var posX, posY: Double
    var normalizedHeight: Double
    var canvasHeight: Double
    var rotation: Double

    init(_ overlay: BurstCaptionOverlay) {
        id              = overlay.id
        text            = overlay.text
        presetID        = overlay.presetID
        posX            = overlay.normalizedPosition.x
        posY            = overlay.normalizedPosition.y
        normalizedHeight = Double(overlay.normalizedHeight)
        canvasHeight    = Double(overlay.canvasHeight)
        rotation        = overlay.rotation
    }

    var toBurstCaptionOverlay: BurstCaptionOverlay {
        var o = BurstCaptionOverlay(presetID: presetID, canvasHeight: CGFloat(canvasHeight))
        o.id                = id
        o.text              = text
        o.normalizedPosition = CGPoint(x: posX, y: posY)
        o.normalizedHeight  = CGFloat(normalizedHeight)
        o.rotation          = rotation
        return o
    }
}

// MARK: - Card status

enum CardStatus: String, Codable {
    case unsent
    case sent
}

// MARK: - Postcard draft snapshot

struct PostcardDraftSnapshot: Identifiable, Codable {
    var id: UUID
    var title: String
    var createdAt: Date
    var lastModified: Date
    var currentStep: Int
    var status: CardStatus

    // Canvas
    var decorativePresetID: String
    var orientationIsLandscape: Bool
    var imageScale: Double
    var imageOffsetWidth: Double
    var imageOffsetHeight: Double
    var filterRawValue: String
    var borderStyle: String
    var borderText: String
    var borderFontName: String
    var borderTextR, borderTextG, borderTextB: Double

    // Text overlays
    var textOverlays: [TextOverlaySnapshot]
    var burstOverlays: [BurstCaptionOverlaySnapshot]?   // Optional for backward-compatible decode
    var qrOverlays: [QROverlaySnapshot]

    // Back of card
    var message: String
    var senderNickname: String?    // Optional for backward-compatible decode
    var recipientNickname: String? // Optional for backward-compatible decode
    var senderName: String
    var senderStreet: String
    var senderCity: String
    var senderState: String
    var senderZip: String
    var senderCountry: String
    var recipientName: String
    var recipientStreet: String
    var recipientCity: String
    var recipientState: String
    var recipientZip: String
    var recipientCountry: String
    var senderEmail: String
    var senderPhone: String
    var recipientEmail: String
    var recipientPhone: String
    var includeQRCode: Bool
    var qrCodeContent: String
    var includeBackMessageQR: Bool
    var backMessageQRContent: String

    // Digital-only cardback ink-free-zone content — all optional for
    // backward-compatible decode of snapshots saved before this feature.
    var greetingId: UUID?
    var greetingSalutation: String?
    var greetingClosing: String?
    var phraseCategory: String?
    var phraseId: UUID?
    var phraseText: String?

    // Supabase card identity — matches draft.cardID, persisted so it survives app restarts
    var cardID: UUID?   // Optional for backward-compatible decode of older snapshots

    // Whether image files exist on disk for this draft
    var hasOriginalImage: Bool
    var hasComposedImage: Bool

    // True for cards restored from Supabase — draft design data is unavailable
    var isRestoredFromServer: Bool?

    // MARK: Build from live draft

    init(draft: PostcardDraft, currentStep: Int, status: CardStatus = .unsent,
         existingID: UUID? = nil, existingCreatedAt: Date? = nil) {
        id           = existingID ?? UUID()
        createdAt    = existingCreatedAt ?? Date()
        lastModified = Date()
        self.currentStep = currentStep
        self.status  = status

        title = draft.recipientName.isEmpty ? "Unsent" : "To \(draft.recipientName)"

        decorativePresetID = draft.decorativePresetID
        orientationIsLandscape = draft.orientation == .landscape
        imageScale             = Double(draft.imageScale)
        imageOffsetWidth       = Double(draft.imageOffset.width)
        imageOffsetHeight      = Double(draft.imageOffset.height)
        filterRawValue         = draft.filter.rawValue
        borderStyle    = draft.border.rawValue
        borderText     = draft.borderText
        borderFontName = draft.borderFontName
        var bR: CGFloat = 0, bG: CGFloat = 0, bB: CGFloat = 0, bA: CGFloat = 0
        UIColor(draft.borderTextColor).getRed(&bR, green: &bG, blue: &bB, alpha: &bA)
        borderTextR = Double(bR); borderTextG = Double(bG); borderTextB = Double(bB)
        textOverlays           = draft.textOverlays.map { TextOverlaySnapshot($0) }
        burstOverlays          = draft.burstOverlays.map { BurstCaptionOverlaySnapshot($0) }
        qrOverlays             = draft.qrOverlays.map { QROverlaySnapshot($0) }

        message          = draft.message
        senderNickname   = draft.senderNickname
        recipientNickname = draft.recipientNickname
        senderName       = draft.senderName
        senderStreet     = draft.senderStreet
        senderCity       = draft.senderCity
        senderState      = draft.senderState
        senderZip        = draft.senderZip
        senderCountry    = draft.senderCountry
        senderEmail      = draft.senderEmail
        senderPhone      = draft.senderPhone
        recipientName    = draft.recipientName
        recipientStreet  = draft.recipientStreet
        recipientCity    = draft.recipientCity
        recipientState   = draft.recipientState
        recipientZip     = draft.recipientZip
        recipientCountry = draft.recipientCountry
        recipientEmail   = draft.recipientEmail
        recipientPhone   = draft.recipientPhone
        includeQRCode         = draft.includeQRCode
        qrCodeContent         = draft.qrCodeContent
        includeBackMessageQR  = draft.includeBackMessageQR
        backMessageQRContent  = draft.backMessageQRContent

        greetingId         = draft.greetingId
        greetingSalutation = draft.greetingSalutation
        greetingClosing    = draft.greetingClosing
        phraseCategory     = draft.phraseCategory
        phraseId           = draft.phraseId
        phraseText         = draft.phraseText

        cardID = draft.cardID

        hasOriginalImage = draft.image != nil
        hasComposedImage = draft.composedImage != nil
    }

    // MARK: Restore to live draft

    func toPostcardDraft(originalImage: UIImage?, composedImage: UIImage?) -> PostcardDraft {
        let d = PostcardDraft()
        d.cardID         = cardID ?? UUID()
        d.image          = originalImage
        d.composedImage  = composedImage
        d.orientation    = orientationIsLandscape ? .landscape : .portrait
        d.imageScale     = CGFloat(imageScale)
        d.imageOffset    = CGSize(width: imageOffsetWidth, height: imageOffsetHeight)
        d.filter         = PostcardFilter(rawValue: filterRawValue) ?? .none
        d.decorativePresetID = decorativePresetID
        d.border          = PostcardBorder(rawValue: borderStyle) ?? .fullBleed
        d.borderText      = borderText
        d.borderFontName  = borderFontName
        d.borderTextColor = Color(red: borderTextR, green: borderTextG, blue: borderTextB)
        d.textOverlays   = textOverlays.map { $0.toTextOverlay }
        d.burstOverlays  = (burstOverlays ?? []).map { $0.toBurstCaptionOverlay }
        d.qrOverlays     = qrOverlays.map { $0.toQROverlay }
        d.message          = message
        d.senderNickname    = senderNickname ?? ""
        d.recipientNickname = recipientNickname ?? ""
        let sp = senderName.components(separatedBy: " ").filter { !$0.isEmpty }
        d.senderFirstName  = sp.first ?? ""
        d.senderLastName   = sp.dropFirst().joined(separator: " ")
        d.senderStreet     = senderStreet
        d.senderCity       = senderCity
        d.senderState      = senderState
        d.senderZip        = senderZip
        d.senderCountry    = senderCountry
        d.senderEmail      = senderEmail
        d.senderPhone      = senderPhone
        let rp = recipientName.components(separatedBy: " ").filter { !$0.isEmpty }
        d.recipientFirstName = rp.first ?? ""
        d.recipientLastName  = rp.dropFirst().joined(separator: " ")
        d.recipientStreet  = recipientStreet
        d.recipientCity    = recipientCity
        d.recipientState   = recipientState
        d.recipientZip     = recipientZip
        d.recipientCountry = recipientCountry
        d.recipientEmail   = recipientEmail
        d.recipientPhone   = recipientPhone
        d.includeQRCode         = includeQRCode
        d.qrCodeContent         = qrCodeContent
        d.includeBackMessageQR  = includeBackMessageQR
        d.backMessageQRContent  = backMessageQRContent

        d.greetingId         = greetingId
        d.greetingSalutation = greetingSalutation ?? ""
        d.greetingClosing    = greetingClosing ?? ""
        d.phraseCategory     = phraseCategory ?? "All"
        d.phraseId           = phraseId
        d.phraseText         = phraseText ?? ""

        return d
    }

    // Human-readable step name for the draft list
    var stepLabel: String {
        switch currentStep {
        case 0:  return "Names"
        case 1:  return "Choosing photo"
        case 2:  return "Styling it"
        case 3:  return "Writing card"
        case 4:  return "Invisible Ink"
        case 5:  return "Addresses"
        case 6:  return "Preview"
        case 7:  return "Ready to send"
        default: return "In progress"
        }
    }

    static func makeRestored(cardID: UUID, recipientName: String, sentAt: Date, isLandscape: Bool) -> PostcardDraftSnapshot {
        let draft = PostcardDraft()
        draft.cardID = cardID
        let parts = recipientName.components(separatedBy: " ").filter { !$0.isEmpty }
        draft.recipientFirstName = parts.first ?? ""
        draft.recipientLastName  = parts.dropFirst().joined(separator: " ")
        draft.orientation        = isLandscape ? .landscape : .portrait
        var s = PostcardDraftSnapshot(draft: draft, currentStep: 7, status: .sent,
                                      existingID: nil, existingCreatedAt: sentAt)
        s.lastModified          = sentAt
        s.isRestoredFromServer  = true
        return s
    }
}
