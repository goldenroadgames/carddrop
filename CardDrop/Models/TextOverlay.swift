import SwiftUI

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
        let pad: CGFloat = 4
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
        case .box:     return "rectangle.roundedcorner"
        case .speech:  return "message.fill"
        case .thought: return "cloud.fill"
        }
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
    var tailFlippedH: Bool            // mirror tail left↔right
    var tailFlippedV: Bool            // mirror tail top↔bottom (speech only)

    static let availableFonts: [(name: String, displayName: String)] = [
        ("HelveticaNeue",      "Helvetica"),
        ("Georgia",            "Georgia"),
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
        fontName           = "HelveticaNeue"
        fontSize           = 16
        self.canvasWidth   = canvasWidth
        textColor          = .black
        bgStyle            = .box
        bgColor            = .white
        tailFlippedH       = false
        tailFlippedV       = false
        rotation           = 0
        isBold             = false
        isItalic           = false
    }
}

// MARK: - Speech Bubble Shape
//
// The shape fills the entire rect. The bubble occupies all but `tailHeight` points
// on the tail side; the triangle protrudes into that reserved space.
// tailOnLeft  – apex of the triangle is on the left side of the base
// tailOnBottom – tail hangs below the bubble (false = tail points upward)

struct SpeechBubbleShape: Shape {
    var tailOnLeft: Bool   = true
    var tailOnBottom: Bool = true
    static let tailHeight: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let tailH = Self.tailHeight
        let bubbleRect: CGRect
        if tailOnBottom {
            bubbleRect = CGRect(x: rect.minX, y: rect.minY,
                                width: rect.width, height: rect.height - tailH)
        } else {
            bubbleRect = CGRect(x: rect.minX, y: rect.minY + tailH,
                                width: rect.width, height: rect.height - tailH)
        }

        var path = Path(roundedRect: bubbleRect, cornerRadius: 10)

        // Base of triangle sits on the bubble edge; apex points away from bubble.
        let baseX: CGFloat = tailOnLeft ? bubbleRect.minX + 18 : bubbleRect.maxX - 34
        let apexX: CGFloat = tailOnLeft ? baseX : baseX + 16

        if tailOnBottom {
            path.move(to:    CGPoint(x: baseX,      y: bubbleRect.maxY))
            path.addLine(to: CGPoint(x: baseX + 16, y: bubbleRect.maxY))
            path.addLine(to: CGPoint(x: apexX,      y: rect.maxY))
        } else {
            path.move(to:    CGPoint(x: baseX,      y: bubbleRect.minY))
            path.addLine(to: CGPoint(x: baseX + 16, y: bubbleRect.minY))
            path.addLine(to: CGPoint(x: apexX,      y: rect.minY))
        }
        path.closeSubpath()

        return path
    }
}

// MARK: - Thought Bubble Shape
//
// tailOnLeft   – dot chain descends toward the left (false = toward the right)
// tailOnBottom – dot chain below the bubble (false = above)

struct ThoughtBubbleShape: Shape {
    var tailOnLeft:   Bool = true
    var tailOnBottom: Bool = true
    static let tailHeight: CGFloat = 30

    func path(in rect: CGRect) -> Path {
        let bubbleRect: CGRect
        if tailOnBottom {
            bubbleRect = CGRect(x: rect.minX, y: rect.minY,
                                width: rect.width, height: rect.height - Self.tailHeight)
        } else {
            bubbleRect = CGRect(x: rect.minX, y: rect.minY + Self.tailHeight,
                                width: rect.width, height: rect.height - Self.tailHeight)
        }
        var path = Path(ellipseIn: bubbleRect)

        if tailOnBottom {
            if tailOnLeft {
                path.addEllipse(in: CGRect(x: bubbleRect.minX + 14, y: bubbleRect.maxY + 2,  width: 10, height: 10))
                path.addEllipse(in: CGRect(x: bubbleRect.minX + 12, y: bubbleRect.maxY + 14, width: 7,  height: 7))
                path.addEllipse(in: CGRect(x: bubbleRect.minX + 10, y: bubbleRect.maxY + 23, width: 4,  height: 4))
            } else {
                path.addEllipse(in: CGRect(x: bubbleRect.maxX - 24, y: bubbleRect.maxY + 2,  width: 10, height: 10))
                path.addEllipse(in: CGRect(x: bubbleRect.maxX - 19, y: bubbleRect.maxY + 14, width: 7,  height: 7))
                path.addEllipse(in: CGRect(x: bubbleRect.maxX - 14, y: bubbleRect.maxY + 23, width: 4,  height: 4))
            }
        } else {
            if tailOnLeft {
                path.addEllipse(in: CGRect(x: bubbleRect.minX + 14, y: bubbleRect.minY - 12, width: 10, height: 10))
                path.addEllipse(in: CGRect(x: bubbleRect.minX + 12, y: bubbleRect.minY - 21, width: 7,  height: 7))
                path.addEllipse(in: CGRect(x: bubbleRect.minX + 10, y: bubbleRect.minY - 27, width: 4,  height: 4))
            } else {
                path.addEllipse(in: CGRect(x: bubbleRect.maxX - 24, y: bubbleRect.minY - 12, width: 10, height: 10))
                path.addEllipse(in: CGRect(x: bubbleRect.maxX - 19, y: bubbleRect.minY - 21, width: 7,  height: 7))
                path.addEllipse(in: CGRect(x: bubbleRect.maxX - 14, y: bubbleRect.minY - 27, width: 4,  height: 4))
            }
        }

        return path
    }
}
