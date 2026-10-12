import Foundation
import Supabase

enum LegalDocumentService {
    enum Document: String, Identifiable {
        case termsOfService = "terms-of-service.md"
        case privacyPolicy = "privacy-policy.md"
        case help = "help.md"

        var id: String { rawValue }
    }

    struct Fetched {
        let text: String
        let lastModified: Date?
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    /// Placeholders a legal/help file may use, filled from zz_config. If a lookup
    /// fails the fallback is used: for card_link_days a number that can only
    /// understate ("at least N days"); for the others the shipped default.
    private static let placeholderFallbacks: [String: Int] = [
        "card_link_days": 30,
        "suspension_delete_days": 180,
        "final_suspension_delete_days": 30,
        "retention_days": 365,
    ]

    private static func fillPlaceholders(in text: String) async -> String {
        struct Row: Decodable { let key: String; let value: String }
        let used = placeholderFallbacks.keys.filter { text.contains("{{\($0)}}") }
        guard !used.isEmpty else { return text }
        let rows: [Row]? = try? await supabase
            .from("zz_config")
            .select("key, value")
            .in("key", value: used)
            .execute()
            .value
        var result = text
        for key in used {
            let days = rows?.first(where: { $0.key == key }).flatMap { Int($0.value) }.flatMap { $0 > 0 ? $0 : nil }
                ?? placeholderFallbacks[key] ?? 0
            result = result.replacingOccurrences(of: "{{\(key)}}", with: String(days))
        }
        return result
    }

    static func fetch(_ document: Document) async throws -> Fetched {
        let url = SupabaseConfig.projectURL
            .appendingPathComponent("storage/v1/object/public/legal/\(document.rawValue)")
        // Bypass any local/CDN caching — these docs get edited and re-uploaded
        // in place at the same URL, so a cached response would silently show
        // stale legal text.
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard var text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        // {{card_link_days}}-style placeholders are replaced with the live settings.
        text = await fillPlaceholders(in: text)
        let lastModifiedHeader = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Last-Modified")
        let lastModified = lastModifiedHeader.flatMap { httpDateFormatter.date(from: $0) }
        return Fetched(text: text, lastModified: lastModified)
    }
}
