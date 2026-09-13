import Foundation
import Supabase

enum CardDeleteService {

    /// Deletes a card and all its children from Supabase.
    /// Order: storage files first, then child DB rows, then parent card row.
    static func delete(cardID: UUID) async {
        let id = cardID.uuidString.lowercased()
        let senderID = (try? await supabase.auth.session.user)?.id.uuidString.lowercased() ?? ""

        // Storage files first (no FK constraints)
        try? await supabase.storage.from("card-images").remove(paths: [
            "\(senderID)/\(id).jpg",
            "\(senderID)/\(id)_back.jpg",
            "\(senderID)/\(id)_back6x9.jpg",
            "\(senderID)/\(id)_back_forLOB.jpg",
            "\(senderID)/\(id)_back6x9_forLOB.jpg",
            "\(senderID)/\(id)_composite.jpg"
        ])

        // Child table rows (before parent to satisfy FK constraints)
        try? await supabase.from("replies")         .delete().eq("card_id", value: id).execute()
        try? await supabase.from("reactions")       .delete().eq("card_id", value: id).execute()
        try? await supabase.from("card_recipients") .delete().eq("card_id", value: id).execute()

        // Parent card row last
        try? await supabase.from("cards").delete().eq("id", value: id).execute()
    }
}
