import Foundation
import Supabase

struct CardReaction: Decodable {
    let emoji: String
    let sent_at: Date?
}

struct CardReply: Decodable, Identifiable {
    var id: UUID
    let reply_text: String?
    let reply_image_url: String?
    let sent_at: Date?
}

enum CardReplyService {

    static func fetchReactions(for cardID: UUID) async throws -> [CardReaction] {
        let rows: [CardReaction] = try await supabase
            .from("reactions")
            .select("emoji, sent_at")
            .eq("card_id", value: cardID.uuidString)
            .execute()
            .value
        return rows
    }

    static func fetchReplies(for cardID: UUID) async throws -> [CardReply] {
        let rows: [CardReply] = try await supabase
            .from("replies")
            .select("id, reply_text, reply_image_url, sent_at")
            .eq("card_id", value: cardID.uuidString)
            .order("sent_at", ascending: false)
            .execute()
            .value
        return rows
    }

    static func fetchCounts(for cardID: UUID) async -> (reactions: Int, replies: Int) {
        async let r = (try? fetchReactions(for: cardID))?.count ?? 0
        async let p = (try? fetchReplies(for: cardID))?.count ?? 0
        return await (r, p)
    }
}
