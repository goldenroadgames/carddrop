import Foundation

/// A curated card from the admin "Manage Marketing Photos" tool
/// (`marketing_cards.in_inspire = true`), shown in the "Get Inspired"
/// gallery. Assets live in the public `marketing-cards` Supabase Storage
/// bucket under anonymized, sender-less paths (no PII).
struct InspireCard: Decodable, Identifiable, Equatable {
    let card_id: UUID
    let sender_id: UUID
    let is_portrait: Bool
    let design_features: String?
    let added_to_marketing_at: Date

    var id: UUID { card_id }

    private var idPath: String { card_id.uuidString.lowercased() }

    /// The finished, composed front — shown with `design_features` in the
    /// before/after toggle's "after" state.
    var frontURL: URL {
        SupabaseConfig.projectURL.appendingPathComponent("storage/v1/object/public/marketing-cards/\(idPath).jpg")
    }

    /// Small JPEG for the gallery grid.
    var thumbnailURL: URL {
        SupabaseConfig.projectURL.appendingPathComponent("storage/v1/object/public/marketing-cards/\(idPath)_thumb.jpg")
    }

    /// The original, pre-edit photo — the before/after toggle's "before"
    /// state. Optional: cards curated before this existed, or sent from a
    /// draft with no original image on disk, won't have one.
    var beforeURL: URL {
        SupabaseConfig.projectURL.appendingPathComponent("storage/v1/object/public/marketing-cards/\(idPath)_before.jpg")
    }

    /// Small JPEG of the before photo — for the gallery grid's ambient
    /// flip, so it isn't loading the full-res before photo into a tiny
    /// tile. Same optionality as beforeURL.
    var beforeThumbnailURL: URL {
        SupabaseConfig.projectURL.appendingPathComponent("storage/v1/object/public/marketing-cards/\(idPath)_before_thumb.jpg")
    }
}
