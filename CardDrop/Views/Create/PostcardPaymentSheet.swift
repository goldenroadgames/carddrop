import SwiftUI
import UIKit
import StripePaymentSheet

/// Payment + promo code, combined in one sheet (a discount is just a
/// modifier on the total, not a separate step). Presented after
/// PostcardAddressStepView hands back the chosen sender/recipient/size.
///
/// Flow: validate the promo code (optional, live preview of the discount)
/// -> tap Pay -> create-postcard-payment-intent (re-validates everything
/// server-side, creates the physical_orders row + Stripe PaymentIntent) ->
/// present Stripe's own PaymentSheet for card entry -> onComplete(true) on
/// success.
struct PostcardPaymentSheet: View {
    let cardID: UUID
    let sender: SavedMailingAddress
    let recipient: SavedMailingAddress
    let price: PostcardPriceOption
    var onComplete: (_ success: Bool, _ orderID: String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var promoCodeText = ""
    @State private var appliedPromo: PromoCodeValidation?
    @State private var promoStatusMessage: String?
    @State private var isValidatingPromo = false

    @State private var isCreatingIntent = false
    @State private var intentErrorMessage: String?

    @State private var isProcessingResult = false
    @State private var pendingOrderID: String?

    private var currency: String { price.currency }

    private var subtotalCents: Int { price.amountCents }
    private var discountCents: Int {
        (appliedPromo?.valid == true) ? (appliedPromo?.discountCents ?? 0) : 0
    }
    private var totalCents: Int {
        (appliedPromo?.valid == true) ? (appliedPromo?.finalAmountCents ?? subtotalCents) : subtotalCents
    }

    private func formatted(_ cents: Int) -> String {
        let amount = Decimal(cents) / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section("Order") {
                        summaryRow(label: price.size == .fourBySix ? "4x6 Postcard" : "6x9 Postcard", value: formatted(subtotalCents))
                        if discountCents > 0 {
                            summaryRow(label: "Promo Discount", value: "-\(formatted(discountCents))")
                                .foregroundColor(.brandBlue)
                        }
                        summaryRow(label: "Total", value: formatted(totalCents))
                            .fontWeight(.semibold)
                    }

                    Section("Promo Code") {
                        HStack {
                            TextField("Enter code", text: $promoCodeText)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .disabled(appliedPromo?.valid == true)
                            if isValidatingPromo {
                                ProgressView()
                            } else if appliedPromo?.valid == true {
                                Button("Remove") { clearPromo() }
                                    .font(.subheadline)
                            } else {
                                // Not using .disabled() here — SwiftUI/List
                                // auto-dims disabled controls inside a List
                                // row regardless of custom colors, which is
                                // exactly the "faded" look we don't want.
                                // Guard the tap itself instead.
                                Button {
                                    let isEmpty = promoCodeText.trimmingCharacters(in: .whitespaces).isEmpty
                                    guard !isEmpty else { return }
                                    Task { await applyPromo() }
                                } label: {
                                    Text("Apply")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                        .background(Color.brandBlue)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if let promoStatusMessage {
                            Text(promoStatusMessage)
                                .font(.subheadline)
                                .foregroundColor(appliedPromo?.valid == true ? .brandBlue : .red)
                        }
                    }

                    if let intentErrorMessage {
                        Section {
                            Text(intentErrorMessage).foregroundColor(.red).font(.subheadline)
                        }
                    }
                }

                Button {
                    Task { await startPayment() }
                } label: {
                    if isCreatingIntent || isProcessingResult {
                        ProgressView().frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        Text("Pay \(formatted(totalCents))")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .background(Color.brandBlue)
                .foregroundColor(.white)
                .cornerRadius(999)
                .disabled(isCreatingIntent || isProcessingResult)
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .navigationTitle("Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem("Cancel", placement: .cancellationAction, style: .filled) { dismiss() }
            }
        }
        .dynamicTypeSize(.medium ... .xxxLarge)
    }

    @ViewBuilder
    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
        }
    }

    private func clearPromo() {
        appliedPromo = nil
        promoStatusMessage = nil
    }

    private func applyPromo() async {
        let code = promoCodeText.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        isValidatingPromo = true
        defer { isValidatingPromo = false }
        do {
            let result = try await PostcardOrderService.validatePromoCode(code: code, size: price.size)
            appliedPromo = result
            promoStatusMessage = result.valid
                ? "Promo code applied."
                : promoReasonMessage(result.reason)
        } catch {
            appliedPromo = nil
            promoStatusMessage = error.localizedDescription
        }
    }

    private func promoReasonMessage(_ reason: String?) -> String {
        switch reason {
        case "not_found": return "That code isn't valid."
        case "inactive": return "That code is no longer active."
        case "not_yet_active": return "That code isn't active yet."
        case "expired": return "That code has expired."
        case "not_applicable_to_size": return "That code doesn't apply to this size."
        case "redemption_limit_reached": return "That code has reached its redemption limit."
        case "already_used": return "You've already used that code."
        default: return "That code isn't valid."
        }
    }

    private func startPayment() async {
        isCreatingIntent = true
        intentErrorMessage = nil
        defer { isCreatingIntent = false }
        do {
            let promoCode = (appliedPromo?.valid == true) ? promoCodeText.trimmingCharacters(in: .whitespaces) : nil
            let intent = try await PostcardOrderService.createPaymentIntent(
                cardID: cardID,
                senderAddressID: sender.id,
                recipientAddressID: recipient.id,
                size: price.size,
                promoCode: promoCode
            )
            pendingOrderID = intent.orderID

            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = "CardDrop"
            configuration.applePay = .init(merchantId: "merchant.com.goldenroadgames", merchantCountryCode: "US")
            // Belt-and-suspenders alongside the server-side payment_method_types
            // restriction to card-only (see create-postcard-payment-intent) —
            // explicitly disallows delayed-notification methods like US bank
            // debit from ever being offered in the sheet.
            configuration.allowsDelayedPaymentMethods = false
            // payment_method_types=["card"] alone doesn't hide Link — Link
            // (including its "Instant Bank Payments"/Bank option) rides
            // along independently of that restriction. .never is the only
            // Display mode that actually disables it (confirmed against
            // PaymentSheet.LinkConfiguration.Display in the SDK source).
            configuration.link.display = .never
            let sheet = PaymentSheet(paymentIntentClientSecret: intent.clientSecret, configuration: configuration)

            guard let presenter = Self.topMostViewController() else {
                intentErrorMessage = "Couldn't present the payment screen. Please try again."
                return
            }
            sheet.present(from: presenter) { result in
                Task { await handlePaymentResult(result) }
            }
        } catch {
            intentErrorMessage = error.localizedDescription
        }
    }

    // PaymentSheet is presented imperatively (rather than via the
    // .paymentSheet SwiftUI modifier) because this view is itself already
    // presented as a .sheet — stacking a second modal through the
    // declarative isPresented-binding modifier is unreliable when nested
    // inside another SwiftUI sheet.
    private static func topMostViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    private func handlePaymentResult(_ result: PaymentSheetResult) async {
        switch result {
        case .completed:
            // Stripe confirmed the charge client-side, but physical_orders
            // is our own table — nothing updates it until we ask Stripe
            // ourselves, server-side, to confirm the same thing.
            isProcessingResult = true
            guard let pendingOrderID else {
                intentErrorMessage = "Payment succeeded, but the order couldn't be finalized. Please contact support."
                isProcessingResult = false
                return
            }
            do {
                let confirmation = try await PostcardOrderService.confirmPayment(orderID: pendingOrderID)
                if confirmation.paid {
                    onComplete(true, pendingOrderID)
                } else {
                    intentErrorMessage = "Payment succeeded, but the order couldn't be finalized. Please contact support."
                    isProcessingResult = false
                }
            } catch {
                intentErrorMessage = error.localizedDescription
                isProcessingResult = false
            }
        case .canceled:
            break
        case .failed(let error):
            intentErrorMessage = error.localizedDescription
        }
    }
}
