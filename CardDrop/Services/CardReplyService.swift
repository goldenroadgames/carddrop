import Foundation
import Supabase

struct CardReaction: Decodable {
    let emoji: String
    let sent_at: Date?
}

struct CardReply: Decodable, Identifiable {
    var id: UUID
    let reply_text: String?
    let sent_at: Date?
}

enum CardReplyService {

    /// Profile-level "Allow replies" switch (users.replies_enabled), mirrored
    /// here by AuthManager so every place that lists replies/reactions follows
    /// the same rule: nothing is shown while the profile switch OR the card's
    /// own switch is off. The server enforces the switches for new replies.
    static var profileRepliesEnabled = true

    private struct CardFlagRow: Decodable { let replies_enabled: Bool? }

    /// This card's own "Allow replies" switch (cards.replies_enabled).
    static func cardRepliesEnabled(for cardID: UUID) async -> Bool {
        let row = try? await supabase
            .from("cards")
            .select("replies_enabled")
            .eq("id", value: cardID.uuidString)
            .single()
            .execute()
            .value as CardFlagRow
        return row?.replies_enabled ?? true
    }

    private static func repliesAllowed(for cardID: UUID) async -> Bool {
        guard profileRepliesEnabled else { return false }
        return await cardRepliesEnabled(for: cardID)
    }

    private struct SetRepliesBody: Encodable {
        let enabled: Bool
        let cardID: String?
        let deleteExisting: Bool
    }

    /// Turns replies + reactions on/off for one card (cardID given) or for the
    /// whole account (cardID nil). deleteExisting (only when turning off)
    /// permanently removes the replies and reactions already received.
    /// Returns false if the server call failed.
    static func setRepliesEnabled(_ enabled: Bool, cardID: UUID?, deleteExisting: Bool) async -> Bool {
        do {
            try await supabase.functions.invoke(
                "set-replies-enabled",
                options: FunctionInvokeOptions(body: SetRepliesBody(
                    enabled: enabled,
                    cardID: cardID?.uuidString,
                    deleteExisting: deleteExisting
                ))
            )
            return true
        } catch {
            return false
        }
    }

    private struct DeleteReplyBody: Encodable { let replyID: String }

    /// Deletes one reply (its text) from the server.
    static func deleteReply(id: UUID) async -> Bool {
        do {
            try await supabase.functions.invoke(
                "delete-reply",
                options: FunctionInvokeOptions(body: DeleteReplyBody(replyID: id.uuidString))
            )
            return true
        } catch {
            return false
        }
    }

    private struct OpenedRow: Decodable { let first_opened_at: Date? }

    /// When a recipient first really viewed this card on the web (cards.first_opened_at),
    /// or nil if not yet. Independent of the "Allow replies" switches.
    static func fetchFirstOpened(for cardID: UUID) async -> Date? {
        let row = try? await supabase
            .from("cards")
            .select("first_opened_at")
            .eq("id", value: cardID.uuidString)
            .single()
            .execute()
            .value as OpenedRow
        return row?.first_opened_at
    }

    static func fetchReactions(for cardID: UUID) async throws -> [CardReaction] {
        guard await repliesAllowed(for: cardID) else { return [] }
        let rows: [CardReaction] = try await supabase
            .from("reactions")
            .select("emoji, sent_at")
            .eq("card_id", value: cardID.uuidString)
            .execute()
            .value
        return rows
    }

    static func fetchReplies(for cardID: UUID) async throws -> [CardReply] {
        guard await repliesAllowed(for: cardID) else { return [] }
        let rows: [CardReply] = try await supabase
            .from("replies")
            .select("id, reply_text, sent_at")
            .eq("card_id", value: cardID.uuidString)
            .order("sent_at", ascending: false)
            .execute()
            .value
        return rows
    }

    private struct ActivityRow: Decodable {
        let card_id: UUID
        let sent_at: Date?
    }

    /// The latest reaction or reply time for each given card (cards with neither
    /// are absent). Drives the Sent gallery order. Empty while the profile switch
    /// has replies off, since nothing is shown then.
    static func fetchLastActivity(for cardIDs: [UUID]) async -> [UUID: Date] {
        guard profileRepliesEnabled, !cardIDs.isEmpty else { return [:] }
        var latest: [UUID: Date] = [:]
        for start in stride(from: 0, to: cardIDs.count, by: 50) {
            let ids = cardIDs[start..<min(start + 50, cardIDs.count)].map(\.uuidString)
            for table in ["reactions", "replies"] {
                let rows: [ActivityRow] = (try? await supabase
                    .from(table)
                    .select("card_id, sent_at")
                    .in("card_id", values: ids)
                    .order("sent_at", ascending: false)
                    .limit(1000)
                    .execute()
                    .value) ?? []
                for row in rows {
                    if let date = row.sent_at, date > (latest[row.card_id] ?? .distantPast) {
                        latest[row.card_id] = date
                    }
                }
            }
        }
        return latest
    }

    static func fetchCounts(for cardID: UUID) async -> (reactions: Int, replies: Int) {
        async let r = (try? fetchReactions(for: cardID))?.count ?? 0
        async let p = (try? fetchReplies(for: cardID))?.count ?? 0
        return await (r, p)
    }
}
