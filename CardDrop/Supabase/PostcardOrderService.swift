import Foundation
import Supabase

enum PostcardOrderServiceError: LocalizedError {
    case other(String)

    var errorDescription: String? {
        switch self {
        case .other(let message): return message
        }
    }
}

/// Result of validating a promo code against the current price for a size —
/// mirrors validate-promo-code's response shape (see supabase/functions).
struct PromoCodeValidation: Decodable {
    let valid: Bool
    let reason: String?
    let promoCodeID: String?
    let discountType: String?
    let discountValue: Int?
    let amountCents: Int?
    let discountCents: Int?
    let finalAmountCents: Int?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case valid, reason, currency
        case promoCodeID = "promoCodeID"
        case discountType = "discountType"
        case discountValue = "discountValue"
        case amountCents = "amountCents"
        case discountCents = "discountCents"
        case finalAmountCents = "finalAmountCents"
    }
}

/// Result of creating the physical_orders row + Stripe PaymentIntent — the
/// clientSecret is what StripePaymentSheet needs to actually collect payment.
struct PostcardPaymentIntent: Decodable {
    let orderID: String
    /// False for a free (promo) order — the server skipped Stripe entirely,
    /// there's no clientSecret, and the order is already ready to submit.
    /// Missing (nil) is treated as true, i.e. the normal paid path.
    let paymentRequired: Bool?
    let clientSecret: String?
    let amountCents: Int
    let discountCents: Int
    let currency: String
}

/// Result of confirm-postcard-payment — `paid` reflects the order's actual
/// status after re-checking with Stripe, not just what the client hoped for.
struct PostcardPaymentConfirmation: Decodable {
    let paid: Bool
    let status: String?
}

/// Result of submit-to-lob — mirrors what LOB's Postcards API returns.
struct LOBSubmissionResult: Decodable {
    let submitted: Bool
    let lobID: String?
    let trackingNumber: String?
    let expectedDeliveryDate: String?
}

private struct ErrorEnvelope: Decodable {
    let error: String?
    let detail: String?
}

enum PostcardOrderService {

    private struct ValidatePromoRequestBody: Encodable {
        let code: String
        let size: String
    }

    /// Calls validate-promo-code. Returns a result even when the code isn't
    /// valid (`valid == false`, with `reason` set) — that's an expected
    /// outcome, not a thrown error; only network/auth/server failures throw.
    static func validatePromoCode(code: String, size: PostcardSize) async throws -> PromoCodeValidation {
        let body = ValidatePromoRequestBody(code: code, size: size.rawValue)
        do {
            let response: PromoCodeValidation = try await supabase.functions
                .invoke("validate-promo-code", options: FunctionInvokeOptions(body: body))
            return response
        } catch let fnError as FunctionsError {
            throw mapFunctionsError(fnError)
        } catch {
            throw PostcardOrderServiceError.other(error.localizedDescription)
        }
    }

    private struct CreatePaymentIntentRequestBody: Encodable {
        let cardID: String
        let senderAddressID: String
        let recipientAddressID: String
        let size: String
        let promoCode: String?
    }

    /// Creates the physical_orders row (pending_payment) and a matching
    /// Stripe PaymentIntent for the server-computed amount. The card, both
    /// addresses, and any promo code are re-validated server-side — this
    /// call never sends an amount, only what the user chose.
    static func createPaymentIntent(
        cardID: UUID,
        senderAddressID: UUID,
        recipientAddressID: UUID,
        size: PostcardSize,
        promoCode: String?
    ) async throws -> PostcardPaymentIntent {
        let body = CreatePaymentIntentRequestBody(
            cardID: cardID.uuidString,
            senderAddressID: senderAddressID.uuidString,
            recipientAddressID: recipientAddressID.uuidString,
            size: size.rawValue,
            promoCode: promoCode
        )
        do {
            let response: PostcardPaymentIntent = try await supabase.functions
                .invoke("create-postcard-payment-intent", options: FunctionInvokeOptions(body: body))
            return response
        } catch let fnError as FunctionsError {
            throw mapFunctionsError(fnError)
        } catch {
            throw PostcardOrderServiceError.other(error.localizedDescription)
        }
    }

    private struct ConfirmPaymentRequestBody: Encodable {
        let orderID: String
    }

    /// Calls confirm-postcard-payment right after StripePaymentSheet reports
    /// .completed — re-verifies the charge with Stripe server-side and flips
    /// the order to 'paid'. `paid == false` (with a status) is an expected
    /// outcome, not a thrown error — e.g. Stripe hasn't finished processing
    /// yet; only network/auth/server failures throw.
    static func confirmPayment(orderID: String) async throws -> PostcardPaymentConfirmation {
        let body = ConfirmPaymentRequestBody(orderID: orderID)
        do {
            let response: PostcardPaymentConfirmation = try await supabase.functions
                .invoke("confirm-postcard-payment", options: FunctionInvokeOptions(body: body))
            return response
        } catch let fnError as FunctionsError {
            throw mapFunctionsError(fnError)
        } catch {
            throw PostcardOrderServiceError.other(error.localizedDescription)
        }
    }

    private struct SubmitToLOBRequestBody: Encodable {
        let orderID: String
        let frontImageURL: String
        let backImageURL: String
    }

    /// Calls submit-to-lob once an order is paid — the front/back images
    /// must already be rendered and uploaded (rendering only happens
    /// on-device; this function can't do it) before calling this.
    static func submitToLOB(orderID: String, frontImageURL: URL, backImageURL: URL) async throws -> LOBSubmissionResult {
        let body = SubmitToLOBRequestBody(
            orderID: orderID,
            frontImageURL: frontImageURL.absoluteString,
            backImageURL: backImageURL.absoluteString
        )
        do {
            let response: LOBSubmissionResult = try await supabase.functions
                .invoke("submit-to-lob", options: FunctionInvokeOptions(body: body))
            return response
        } catch let fnError as FunctionsError {
            throw mapFunctionsError(fnError)
        } catch {
            throw PostcardOrderServiceError.other(error.localizedDescription)
        }
    }

    private static func mapFunctionsError(_ fnError: FunctionsError) -> PostcardOrderServiceError {
        if case .httpError(_, let data) = fnError,
           let body = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            return .other(body.detail ?? body.error ?? fnError.localizedDescription)
        }
        return .other(fnError.localizedDescription)
    }
}
