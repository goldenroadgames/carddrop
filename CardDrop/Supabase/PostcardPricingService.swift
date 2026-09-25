import Foundation
import Supabase

enum PostcardSize: String, Codable, CaseIterable {
    case fourBySix = "4x6"
    case sixByNine = "6x9"
}

/// One size's current price + display copy, resolved server-side by the
/// zz_postcard_current_pricing view (handles overlapping standing/special
/// price windows — see migration 024) and merged with the standing
/// zz_postcard_products tagline.
struct PostcardPriceOption: Identifiable, Equatable {
    var id: PostcardSize { size }
    let size: PostcardSize
    let amountCents: Int
    let currency: String
    let productDescription: String
    let specialDescription: String?

    var formattedPrice: String {
        let amount = Decimal(amountCents) / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }
}

enum PostcardPricingServiceError: LocalizedError {
    case other(String)

    var errorDescription: String? {
        switch self {
        case .other(let message): return message
        }
    }
}

enum PostcardPricingService {

    private struct PricingRow: Decodable {
        let size: String
        let amountCents: Int
        let currency: String
        let productDescriptionOverride: String?
        let specialDescription: String?

        enum CodingKeys: String, CodingKey {
            case size, currency
            case amountCents = "amount_cents"
            case productDescriptionOverride = "product_description_override"
            case specialDescription = "special_description"
        }
    }

    private struct ProductRow: Decodable {
        let size: String
        let productDescription: String

        enum CodingKeys: String, CodingKey {
            case size
            case productDescription = "product_description"
        }
    }

    /// Fetches both sizes' current pricing in parallel and merges each
    /// price row with its standing catalog tagline (or the price row's own
    /// override, when set — see [[project_lob_integration_progress]] for
    /// the override-vs-standing-tagline decision).
    static func fetchCurrentPricing() async throws -> [PostcardPriceOption] {
        do {
            async let pricingTask: [PricingRow] = supabase
                .from("zz_postcard_current_pricing")
                .select()
                .execute()
                .value
            async let productsTask: [ProductRow] = supabase
                .from("zz_postcard_products")
                .select()
                .execute()
                .value

            let (pricingRows, productRows) = try await (pricingTask, productsTask)
            let taglines = Dictionary(uniqueKeysWithValues: productRows.map { ($0.size, $0.productDescription) })

            return pricingRows.compactMap { row in
                guard let size = PostcardSize(rawValue: row.size) else { return nil }
                let tagline = row.productDescriptionOverride ?? taglines[row.size] ?? ""
                return PostcardPriceOption(
                    size: size,
                    amountCents: row.amountCents,
                    currency: row.currency,
                    productDescription: tagline,
                    specialDescription: row.specialDescription
                )
            }
        } catch {
            throw PostcardPricingServiceError.other(error.localizedDescription)
        }
    }
}
