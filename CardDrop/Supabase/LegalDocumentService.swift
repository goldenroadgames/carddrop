import Foundation

enum LegalDocumentService {
    enum Document: String, Identifiable {
        case termsOfService = "terms-of-service.md"
        case privacyPolicy = "privacy-policy.md"

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

    static func fetch(_ document: Document) async throws -> Fetched {
        let url = SupabaseConfig.projectURL
            .appendingPathComponent("storage/v1/object/public/legal/\(document.rawValue)")
        // Bypass any local/CDN caching — these docs get edited and re-uploaded
        // in place at the same URL, so a cached response would silently show
        // stale legal text.
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        let lastModifiedHeader = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Last-Modified")
        let lastModified = lastModifiedHeader.flatMap { httpDateFormatter.date(from: $0) }
        return Fetched(text: text, lastModified: lastModified)
    }
}
