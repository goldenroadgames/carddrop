import Foundation
import UIKit
import Supabase

enum ModerationResult {
    case clean
    case flagged([String])   // human-readable category names
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
    }

    private struct Response: Decodable {
        let status: String
        let categories: [String]?
    }

    /// Check one or more text strings.
    static func check(texts: [String]) async -> ModerationResult {
        let nonEmpty = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return .clean }
        return await perform(Request(texts: nonEmpty, image: nil))
    }

    /// Check an image (resized to 512px max to keep payload small).
    static func check(image: UIImage) async -> ModerationResult {
        let resized = image.moderationThumbnail()
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { return .unavailable }
        return await perform(Request(texts: nil, image: jpeg.base64EncodedString()))
    }

    // MARK: - Request

    private static func perform(_ body: Request) async -> ModerationResult {
        do {
            let response: Response = try await supabase.functions
                .invoke("moderate-content", options: FunctionInvokeOptions(body: body))
            if response.status == "flagged" {
                return .flagged(response.categories ?? [])
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
