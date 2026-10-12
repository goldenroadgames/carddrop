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

    /// Days a card link stays live after it is sent (zz_config card_link_days).
    /// The help text says "at least N days", so if the lookup fails this falls
    /// back to 30 — a number that can only understate what we give.
    private static func cardLinkDays() async -> Int {
        struct Row: Decodable { let value: String }
        let row = try? await supabase
            .from("zz_config")
            .select("value")
            .eq("key", value: "card_link_days")
            .single()
            .execute()
            .value as Row
        if let row, let days = Int(row.value), days > 0 { return days }
        return 30
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
        // {{card_link_days}} in a legal/help file is replaced with the live setting.
        if text.contains("{{card_link_days}}") {
            text = text.replacingOccurrences(of: "{{card_link_days}}", with: String(await cardLinkDays()))
        }
        let lastModifiedHeader = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Last-Modified")
        let lastModified = lastModifiedHeader.flatMap { httpDateFormatter.date(from: $0) }
        return Fetched(text: text, lastModified: lastModified)
    }
}
