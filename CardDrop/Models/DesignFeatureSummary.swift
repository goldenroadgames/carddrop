import Foundation

// MARK: - Design-feature bullet list
//
// Generates a technical, tag-style bullet list (newline-separated for
// storage) describing the STYLE CHOICES used on a card's front (orientation,
// filter, border, overlays, banner, invisible ink) for storage in
// cards.design_features. "Category: Value" lines for multi-valued
// attributes (Orientation/Filter/Border/Greetings/Text), bare labels for
// pure on/off features (Burst Caption/Invisible Ink). Subject Cutout is
// folded into the Greetings line as one of its attributes, not its own
// bullet — it's only ever paired with the Greetings banner in practice.
// Orientation always appears, first; everything else only if actually used
// — no "Invisible Ink: unused" placeholders. Never includes any
// user-entered text (message, greeting word, names, addresses, etc.) — this
// column is safe to be publicly readable and safe to carry over into
// marketing_cards.
extension PostcardDraft {

    /// Newline-separated bullet list of this card's front design features.
    /// Orientation and Border are always present; every other line only if
    /// that feature is actually used. Split on "\n" for display.
    func designFeatureSummary() -> String? {
        var features: [String] = []

        features.append("Orientation: \(orientation == .portrait ? "Portrait" : "Landscape")")

        if filter != .none {
            features.append("Filter: \(filter.rawValue)")
        }

        switch border {
        case .decorative:  features.append("Border: Decorative")
        case .customText:  features.append("Border: Custom Text")
        case .whiteBorder: features.append("Border: White")
        case .fullBleed:   features.append("Border: Full Bleed")
        }

        if let greeting = greetingsOverlays.first {
            var attributes: [String] = []
            if subjectCutoutImage != nil {
                attributes.append("Subject Cutout")
            }
            if greeting.haloEnabled {
                attributes.append("Halo")
            }
            // Rendered as badgeColorChoice.color.opacity(backgroundOpacity)
            // (see PostcardFrontCanvas) — badgeColorChoice itself can be
            // .transparent (always fully see-through regardless of the
            // opacity slider), so that has to be checked first.
            if greeting.badgeColorChoice == .transparent || greeting.backgroundOpacity == 0 {
                attributes.append("Transparent Background")
            } else if greeting.backgroundOpacity == 1 {
                attributes.append("Solid \(greeting.badgeColorChoice.rawValue.capitalized) Background")
            } else {
                attributes.append("Semi-Transparent \(greeting.badgeColorChoice.rawValue.capitalized) Background")
            }
            features.append("Greetings: \(attributes.joined(separator: ", "))")
        }

        // Distinct overlay shapes, first-occurrence order — includes .none
        // ("no container") now, unlike earlier revisions of this generator.
        var seenShapes: [TextBgStyle] = []
        for overlay in textOverlays where !seenShapes.contains(overlay.bgStyle) {
            seenShapes.append(overlay.bgStyle)
        }
        for shape in seenShapes {
            switch shape {
            case .box:     features.append("Text: Box")
            case .rectangle: features.append("Text: Rectangle")
            case .speech:  features.append("Text: Speech Bubble")
            case .thought: features.append("Text: Thought Bubble")
            case .none:    features.append("Text: no container")
            }
        }

        if !burstOverlays.isEmpty {
            features.append("Burst Caption")
        }

        // This describes the FRONT design only — matches the actual
        // send-time logic for the front's invisible-ink QR (PreviewSendStepView's
        // frontInk). includeQRCode itself is unreliable (defaults to true
        // regardless of whether a QR was actually added).
        let hasFrontQR = qrOverlays.contains { !$0.userInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if hasFrontQR {
            features.append("Invisible Ink")
        }

        return features.joined(separator: "\n")
    }
}
