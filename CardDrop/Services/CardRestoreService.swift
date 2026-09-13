import Foundation
import UIKit
import Supabase

enum CardRestoreService {

    private struct ServerCard: Decodable {
        let id: UUID
        let recipient_first_name: String?
        let recipient_last_name: String?
        let sent_at: Date?
        let is_portrait: Bool?
    }

    static func syncIfNeeded(userID: String, draftManager: DraftManager) async {
        guard !userID.isEmpty else { return }

        // Fetch all card IDs from server for this user
        guard let serverCards = try? await supabase
            .from("cards")
            .select("id, recipient_first_name, recipient_last_name, sent_at, is_portrait")
            .eq("sender_id", value: userID)
            .order("sent_at", ascending: false)
            .execute()
            .value as [ServerCard]
        else { return }

        // Find cards missing locally
        let localCardIDs = Set(draftManager.drafts.compactMap { $0.cardID })
        let missing = serverCards.filter { !localCardIDs.contains($0.id) }

        for card in missing {
            await restoreCard(card, draftManager: draftManager)
        }
    }

    private static func restoreCard(_ card: ServerCard, draftManager: DraftManager) async {
        // Download card front image
        guard let senderID = (try? await supabase.auth.session.user)?.id.uuidString.lowercased() else { return }
        let path = "\(senderID)/\(card.id.uuidString).jpg"
        guard let imageData = try? await supabase.storage
            .from("card-images")
            .download(path: path)
        else { return }

        // Save card front locally
        if let image = UIImage(data: imageData) {
            draftManager.saveFront(image, cardID: card.id)
        }

        // Build a minimal snapshot
        let firstName = card.recipient_first_name ?? ""
        let lastName  = card.recipient_last_name  ?? ""
        let name = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        let sentAt = card.sent_at ?? Date()
        let isLandscape = !(card.is_portrait ?? false)

        draftManager.restoreFromServer(
            cardID: card.id,
            recipientName: name,
            sentAt: sentAt,
            isLandscape: isLandscape
        )
    }
}
