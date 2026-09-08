import Foundation
import Supabase

// One row per recipient a card was actually sent to — populated by
// insertEmailRecipients/insertMessageRecipients in SendOptionsView
// (Views/Create/PreviewSendStepView.swift).
// `send_method` is nil for rows written before that column existed.
struct CardRecipientRecord: Decodable, Identifiable {
    let id: UUID
    let first_name: String?
    let last_name: String?
    let email: String?
    let phone: String?
    let send_method: String?
    let created_at: Date

    var displayName: String {
        let name = [first_name, last_name].compactMap { $0 }.joined(separator: " ")
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        return email ?? phone ?? "Recipient"
    }

    var modeLabel: String {
        switch send_method {
        case "email": return "Email"
        case "text": return "Text Message"
        case "postcard": return "Mailed Postcard"
        default: return "Digital"
        }
    }

    var modeIcon: String {
        switch send_method {
        case "email": return "envelope"
        case "text": return "message"
        case "postcard": return "photo"
        default: return "paperplane"
        }
    }
}

enum CardRecipientService {
    static func fetchHistory(for cardID: UUID) async throws -> [CardRecipientRecord] {
        let rows: [CardRecipientRecord] = try await supabase
            .from("card_recipients")
            .select("id, first_name, last_name, email, phone, send_method, created_at")
            .eq("card_id", value: cardID.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows
    }
}
