import UIKit

enum TeaserImageGenerator {

    /// Generates a teaser image for MMS: card thumbnail with message preview and sender name.
    /// Output is ~600×400px, under 600KB.
    static func generate(cardFront: UIImage, message: String, senderName: String) -> UIImage {
        let size = CGSize(width: 600, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // Background
            UIColor(white: 0.12, alpha: 1).setFill()
            cgCtx.fill(CGRect(origin: .zero, size: size))

            // Card thumbnail — left side, vertically centered with padding
            let thumbPadding: CGFloat = 24
            let thumbMaxW: CGFloat = 240
            let thumbMaxH: CGFloat = size.height - thumbPadding * 2
            let imgRatio = cardFront.size.width / cardFront.size.height
            let thumbW: CGFloat
            let thumbH: CGFloat
            if imgRatio >= 1 {
                thumbW = min(thumbMaxW, thumbMaxH * imgRatio)
                thumbH = thumbW / imgRatio
            } else {
                thumbH = min(thumbMaxH, thumbMaxW / imgRatio)
                thumbW = thumbH * imgRatio
            }
            let thumbX = thumbPadding
            let thumbY = (size.height - thumbH) / 2
            let thumbRect = CGRect(x: thumbX, y: thumbY, width: thumbW, height: thumbH)

            // Clip and draw card image
            let thumbPath = UIBezierPath(roundedRect: thumbRect, cornerRadius: 6)
            cgCtx.saveGState()
            thumbPath.addClip()
            cardFront.draw(in: thumbRect)
            cgCtx.restoreGState()

            // Subtle shadow on thumb
            cgCtx.setShadow(offset: CGSize(width: 0, height: 4), blur: 12,
                            color: UIColor.black.withAlphaComponent(0.6).cgColor)
            UIColor.clear.setFill()
            cgCtx.restoreGState()

            // Text area — right of thumbnail
            let textX = thumbX + thumbW + 20
            let textW = size.width - textX - thumbPadding
            var textY: CGFloat = thumbPadding + 8

            // "CardDrop" label
            let appLabel = "CardDrop" as NSString
            let appAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor(white: 0.45, alpha: 1),
                .kern: 1.5
            ]
            appLabel.draw(at: CGPoint(x: textX, y: textY), withAttributes: appAttrs)
            textY += 20

            // Message preview — truncated at word boundary, max 60 chars
            let preview = truncated(message, to: 60)
            let messageAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .regular),
                .foregroundColor: UIColor(white: 0.92, alpha: 1)
            ]
            let messageRect = CGRect(x: textX, y: textY, width: textW,
                                     height: size.height - textY - 60)
            (preview as NSString).draw(in: messageRect, withAttributes: messageAttrs)

            // "From [name]" at bottom right
            let fromText = "From \(senderName)" as NSString
            let fromAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: UIColor(white: 0.55, alpha: 1)
            ]
            let fromSize = fromText.size(withAttributes: fromAttrs)
            fromText.draw(at: CGPoint(x: size.width - fromSize.width - thumbPadding,
                                      y: size.height - fromSize.height - thumbPadding),
                          withAttributes: fromAttrs)
        }
    }

    // MARK: - Helpers

    private static func truncated(_ text: String, to limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let cut = trimmed.prefix(limit)
        // Walk back to last word boundary
        if let lastSpace = cut.lastIndex(of: " ") {
            return String(cut[..<lastSpace]) + "…"
        }
        return String(cut) + "…"
    }
}
