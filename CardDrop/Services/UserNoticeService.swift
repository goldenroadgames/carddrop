import Foundation
import Supabase

/// Server-written notices for the signed-in user (complaint warnings, account
/// suspension). Read once at launch of My Cards, shown, then marked seen.
enum UserNoticeService {

    struct Notice: Decodable, Identifiable {
        let id: UUID
        let kind: String      // "warning" | "ban"
        let message: String
    }

    static func fetchUnseen() async -> [Notice] {
        (try? await supabase
            .from("user_notices")
            .select("id, kind, message")
            .filter("seen_at", operator: "is", value: "null")
            .order("created_at", ascending: true)
            .execute()
            .value) ?? []
    }

    private struct SeenUpdate: Encodable {
        let seen_at: String
    }

    static func markSeen(_ notices: [Notice]) async {
        guard !notices.isEmpty else { return }
        let update = SeenUpdate(seen_at: ISO8601DateFormatter().string(from: Date()))
        try? await supabase
            .from("user_notices")
            .update(update)
            .in("id", values: notices.map { $0.id.uuidString })
            .execute()
    }
}
