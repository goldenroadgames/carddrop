import Foundation
import UIKit
import Supabase

enum ModerationResult {
    case clean
    case flagged([String])   // human-readable category names
}

struct ModerationService {

    // Cached after first fetch — thresholds rarely change mid-session, and
    // this avoids a round trip on every moderation check. Keyed by OpenAI's
    // raw category name (e.g. "harassment"), not the human-readable label.
    // A category with no entry here keeps the strict default (see
    // OAIItem.flaggedCategoryNames): block whenever OpenAI's own boolean
    // flag is true.
    private static var cachedThresholds: [String: Double]?

    private static func thresholds() async -> [String: Double] {
        if let cachedThresholds { return cachedThresholds }
        struct Row: Decodable { let key: String; let value: String }
        guard let rows: [Row] = try? await supabase
            .from("zz_config")
            .select("key, value")
            .like("key", pattern: "moderation_threshold_%")
            .execute()
            .value
        else {
            return [:]
        }
        var result: [String: Double] = [:]
        for row in rows {
            let category = row.key.replacingOccurrences(of: "moderation_threshold_", with: "")
            if let score = Double(row.value) { result[category] = score }
        }
        cachedThresholds = result
        return result
    }

    /// Check one or more text strings.
    static func check(texts: [String]) async -> ModerationResult {
        let nonEmpty = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return .clean }
        guard !APIKeys.openAI.isEmpty else {
            print("⚠️ ModerationService: No API key — skipping text check")
            return .clean
        }
        let body: [String: Any] = ["input": nonEmpty]
        return await perform(body: body)
    }

    /// Check an image (resized to 512px max to keep payload small).
    static func check(image: UIImage) async -> ModerationResult {
        guard !APIKeys.openAI.isEmpty else {
            print("⚠️ ModerationService: No API key — skipping image check")
            return .clean
        }
        let resized = image.moderationThumbnail()
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { return .clean }
        let base64 = jpeg.base64EncodedString()
        let input: [[String: Any]] = [[
            "type": "image_url",
            "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
        ]]
        let body: [String: Any] = ["input": input]
        return await perform(body: body)
    }

    // MARK: - Shared request performer

    private static func perform(body: [String: Any]) async -> ModerationResult {
        guard let url = URL(string: "https://api.openai.com/v1/moderations") else { return .clean }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(APIKeys.openAI)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let thresholds = await thresholds()

        guard let (data, httpResponse) = try? await URLSession.shared.data(for: request) else {
            print("⚠️ ModerationService: network request failed")
            return .clean
        }

        let statusCode = (httpResponse as? HTTPURLResponse)?.statusCode ?? 200
        if statusCode == 429 {
            print("⏳ ModerationService: rate limited, retrying in 3s…")
            try? await Task.sleep(for: .seconds(3))
            guard let (retryData, _) = try? await URLSession.shared.data(for: request),
                  let response = try? JSONDecoder().decode(OAIResponse.self, from: retryData)
            else {
                print("⚠️ ModerationService: retry also failed — blocking to be safe")
                return .flagged(["content could not be verified"])
            }
            let flagged = response.results.flatMap { $0.flaggedCategoryNames(thresholds: thresholds) }
            return flagged.isEmpty ? .clean : .flagged(flagged)
        }

        guard let response = try? JSONDecoder().decode(OAIResponse.self, from: data) else {
            print("⚠️ ModerationService: failed to decode response")
            return .clean
        }

        var flagged: Set<String> = []
        for result in response.results {
            flagged.formUnion(result.flaggedCategoryNames(thresholds: thresholds))
        }
        return flagged.isEmpty ? .clean : .flagged(Array(flagged).sorted())
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

// MARK: - Response models

private struct OAIResponse: Decodable {
    let results: [OAIItem]
}

private struct OAIItem: Decodable {
    let categories: [String: Bool]
    let category_scores: [String: Double]

    // A category only counts as flagged if its score clears OUR threshold
    // (see zz_config's moderation_threshold_* rows, migration 031) — not
    // just OpenAI's own boolean, which proved too strict for "harassment"
    // in a novelty-postcard app (mild jabs are the whole point). A category
    // with no configured threshold falls back to 0.0 — i.e. OpenAI's
    // boolean alone still blocks it, same as before this change.
    func flaggedCategoryNames(thresholds: [String: Double]) -> [String] {
        let labels: [String: String] = [
            "harassment":              "harassment",
            "harassment/threatening":  "threatening harassment",
            "hate":                    "hate speech",
            "hate/threatening":        "threatening hate speech",
            "illicit":                 "illicit content",
            "illicit/violent":         "violent illicit content",
            "self-harm":               "self-harm",
            "self-harm/intent":        "self-harm",
            "self-harm/instructions":  "self-harm",
            "sexual":                  "sexually explicit content",
            "sexual/minors":           "content involving minors",
            "violence":                "violent content",
            "violence/graphic":        "graphic violence",
        ]
        return categories
            .filter { $0.value }
            .filter { (category_scores[$0.key] ?? 1.0) >= (thresholds[$0.key] ?? 0.0) }
            .compactMap { labels[$0.key] ?? $0.key }
            .sorted()
    }
}
