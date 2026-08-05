import Foundation
import Supabase

/// A salutation/closing combo for the digital-only cardback ink-free zone.
/// `{recipient}`/`{sender}` placeholders are filled in at selection time.
struct CardbackGreeting: Decodable, Identifiable {
    let id: UUID
    let salutation_template: String
    let closing_template: String
    let sort_order: Int

    func filled(sender: String, recipient: String) -> (salutation: String, closing: String) {
        func fill(_ s: String) -> String {
            s.replacingOccurrences(of: "{recipient}", with: recipient)
             .replacingOccurrences(of: "{sender}", with: sender)
        }
        return (fill(salutation_template), fill(closing_template))
    }
}

/// A standalone line of text for the digital-only cardback ink-free zone.
struct CardbackPhrase: Decodable, Identifiable {
    let id: UUID
    let category: String
    let text: String
    let sort_order: Int
}

enum CardBackContentService {
    static func fetchGreetings() async -> [CardbackGreeting] {
        (try? await supabase
            .from("cardback_greetings")
            .select("id, salutation_template, closing_template, sort_order")
            .order("sort_order")
            .execute()
            .value) ?? []
    }

    static func fetchPhrases() async -> [CardbackPhrase] {
        (try? await supabase
            .from("cardback_phrases")
            .select("id, category, text, sort_order")
            .order("sort_order")
            .execute()
            .value) ?? []
    }
}
