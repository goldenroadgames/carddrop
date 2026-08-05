import SwiftUI
import StoreKit

/// Sheet presented when the user taps "Upgrade to Permanent Storage" in ProfileView.
struct StorageUpgradeView: View {
    var onUpgradeComplete: () -> Void

    @StateObject private var store = StorePurchaseService()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Hero
                    VStack(spacing: 12) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(Color.purple)
                            .padding(.top, 32)

                        Text("Permanent Card Storage")
                            .font(.title2.weight(.bold))

                        Text("Your digital cards live forever — not just 30 days.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // What you get
                    VStack(alignment: .leading, spacing: 14) {
                        featureRow("infinity", .purple, "Cards never expire")
                        featureRow("link", .blue, "Share links stay live indefinitely")
                        featureRow("clock.arrow.circlepath", .green, "Clone cards anytime — originals preserved on device")
                        featureRow("person.fill.checkmark", .orange, "One-time purchase — not a subscription")
                    }
                    .padding(.horizontal, 32)

                    Divider().padding(.horizontal)

                    // Price and purchase
                    VStack(spacing: 12) {
                        if let product = store.product {
                            Text(product.displayPrice)
                                .font(.system(size: 36, weight: .bold))
                            Text("one-time, covers all your cards")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Button(action: { Task { await store.purchase() } }) {
                                Group {
                                    if store.isLoading {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                    } else {
                                        Text("Unlock Permanent Storage")
                                            .fontWeight(.semibold)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                    }
                                }
                            }
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .disabled(store.isLoading)
                            .padding(.top, 4)

                        } else if store.isLoading {
                            ProgressView("Loading…")
                        } else {
                            Text("Product unavailable — try again later.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if let error = store.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }

                        Button("Restore Purchase") {
                            Task { await store.restorePurchases() }
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .disabled(store.isLoading)
                    }
                    .padding(.horizontal)

                    finePrint
                }
                .padding(.bottom, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: store.isPurchased) {
                if store.isPurchased {
                    onUpgradeComplete()
                    dismiss()
                }
            }
            .onAppear {
                store.onPurchaseComplete = onUpgradeComplete
                Task { await store.checkCurrentEntitlements() }
            }
        }
        .dynamicTypeSize(.medium ... .xxxLarge)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func featureRow(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(color)
                .cornerRadius(7)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }

    private var finePrint: some View {
        Text("Cards sent on the free tier before purchase will remain accessible for their original 30-day window. This purchase applies to your account and is subject to our Terms of Service.")
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
    }
}
