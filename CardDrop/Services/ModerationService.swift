import Foundation
import UIKit
import Supabase

/// One flagged field of the card and what it was flagged for ("The message", ["hate speech"]).
struct FlaggedField {
    let label: String
    let categories: [String]
}

/// A content_flagged reply's per-kind detail from send-card / submit-to-lob:
/// a photo or text was flagged, and for what.
struct FlaggedPart: Decodable {
    let kind: String          // "photo" | "text"
    let categories: [String]
    let images: [String]?     // photo only: "front" | "back" | "original"
}

enum ModerationResult {
    case clean
    // Human-readable category names, plus an optional warning that repeated
    // blocked content can lead to suspension (see ModerationService.warningMessage).
    // fields = which typed fields were flagged, when the caller checked labelled
    // items (check(items:)); empty otherwise.
    case flagged([String], warning: String?, fields: [FlaggedField])
    case unavailable         // the check couldn't run (offline, server error): block and ask to retry
}

// Content-safety checks for the create flow. The checks run on our server
// (the moderate-content Edge Function, which holds the OpenAI key and the
// zz_config moderation_threshold_* rows) — no key lives in the app.
//
// If the check can't be reached (offline, server error) the result is
// .unavailable and the user is blocked with a "try again" message — content is
// never let through unchecked. send-card re-checks everything it receives
// before a card is stored, and refuses if it can't run the check.
struct ModerationService {

    private struct Request: Encodable {
        let texts: [String]?
        let image: String?   // base64 JPEG
        let deviceUUID: String
    }

    private struct FlaggedText: Decodable {
        let index: Int
        let categories: [String]
    }

    private struct Response: Decodable {
        let status: String
        let categories: [String]?
        let flaggedTexts: [FlaggedText]?
        let warning: String?    // "warn" | "final" | "none"
        let suspended: Bool?
    }

    /// Wording for the server's repeated-blocked-content warning levels. The
    /// server counts every blocked photo or text item toward a suspension, with
    /// separate limits for photos and text.
    static func warningMessage(_ level: String?) -> String? {
        switch level {
        case "warn":  return "Blocked content adds up, and too much will lead to your account being suspended."
        case "final": return "Your next blocked item will suspend your account."
        default:      return nil
        }
    }

    /// Check one or more text strings.
    static func check(texts: [String]) async -> ModerationResult {
        let nonEmpty = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return .clean }
        return await perform(Request(texts: nonEmpty, image: nil, deviceUUID: UserService.deviceUUID.uuidString))
    }

    /// Check labelled text items ("The message", "A caption"...). Same check as
    /// check(texts:), but a flagged result says which items were flagged.
    /// Empty items are skipped, so the labels line up with what is sent.
    static func check(items: [(label: String, text: String)]) async -> ModerationResult {
        let kept = items
            .map { (label: $0.label, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty }
        guard !kept.isEmpty else { return .clean }
        return await perform(
            Request(texts: kept.map { $0.text }, image: nil, deviceUUID: UserService.deviceUUID.uuidString),
            labels: kept.map { $0.label }
        )
    }

    /// "hate speech", "hate speech and harassment", "a, b and c". A bare
    /// "self-harm" reads as "self-harm content" after "may contain".
    static func joinedCategories(_ cats: [String]) -> String {
        let named = cats.map { $0 == "self-harm" ? "self-harm content" : $0 }
        switch named.count {
        case 0, 1: return named.first ?? ""
        default:   return named.dropLast().joined(separator: ", ") + " and " + named[named.count - 1]
        }
    }

    /// The alert text for a flagged create-step check. With field detail:
    /// "The message may contain hate speech. A caption may contain ...".
    /// Without it, the caller's own generic wording.
    static func alertMessage(categories: [String], fields: [FlaggedField], warning: String?, fallback: String) -> String {
        var body = fallback
        if !fields.isEmpty {
            // One line per label; the same label flagged twice (two captions) merges.
            var order: [String] = []
            var cats: [String: [String]] = [:]
            for f in fields {
                if cats[f.label] == nil { order.append(f.label) }
                for c in f.categories where !(cats[f.label] ?? []).contains(c) { cats[f.label, default: []].append(c) }
            }
            let lines = order.map { "\($0) may contain \(joinedCategories(cats[$0] ?? []))." }
            body = lines.joined(separator: " ") + " Please review " + (order.count == 1 ? "it" : "these") + " and try again."
        }
        return body + (warning.map { "\n\n" + $0 } ?? "")
    }

    /// The detail lines for a refused Send or mailed order: which image or
    /// text was flagged, and for what (see send-card / submit-to-lob).
    static func sendDetails(_ flagged: [FlaggedPart]) -> [String] {
        flagged.map { part -> String in
            let cats = joinedCategories(part.categories)
            guard part.kind == "photo" else { return "Text on your card may contain \(cats)." }
            let names = (part.images ?? []).compactMap { role -> String? in
                switch role {
                case "front":    return "The card front"
                case "back":     return "The card back"
                case "original": return "The original photo"
                default:         return nil
                }
            }
            guard !names.isEmpty else { return "An image on your card may contain \(cats)." }
            let subject = names.count == 1
                ? names[0]
                : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1].lowercased()
            let hint = (part.images ?? []).contains(where: { $0 == "front" || $0 == "original" })
                ? " Try changing the photo or its styling." : ""
            return "\(subject) may contain \(cats).\(hint)"
        }
    }

    /// Check an image (resized to 512px max to keep payload small).
    static func check(image: UIImage) async -> ModerationResult {
        let resized = image.moderationThumbnail()
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { return .unavailable }
        return await perform(Request(texts: nil, image: jpeg.base64EncodedString(), deviceUUID: UserService.deviceUUID.uuidString))
    }

    // MARK: - Request

    private static func perform(_ body: Request, labels: [String]? = nil) async -> ModerationResult {
        do {
            let response: Response = try await supabase.functions
                .invoke("moderate-content", options: FunctionInvokeOptions(body: body))
            if response.status == "flagged" {
                if response.suspended == true {
                    // Too many blocked items: the account was just suspended.
                    SuspensionMonitor.trigger()
                    return .flagged(response.categories ?? [], warning: "Your account has been suspended.", fields: [])
                }
                let fields: [FlaggedField] = (response.flaggedTexts ?? []).compactMap { f in
                    guard let labels, labels.indices.contains(f.index) else { return nil }
                    return FlaggedField(label: labels[f.index], categories: f.categories)
                }
                return .flagged(response.categories ?? [], warning: warningMessage(response.warning), fields: fields)
            }
            return .clean
        } catch {
            print("⚠️ ModerationService: check unavailable (\(error.localizedDescription))")
            return .unavailable
        }
    }
}

// MARK: - UIImage resize helper

private extension UIImage {
    /// Shrinks to 512px max dimension — sufficient for moderation, keeps payload small.
    func moderationThumbnail() -> UIImage {
        let maxDim: CGFloat = 512
        let scale = min(maxDim / size.width, maxDim / size.height, 1.0)
        guard scale < 1.0 else { return self }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
