import Combine
import StoreKit
import Supabase

class StorePurchaseService: ObservableObject {
    static let permanentStorageID = "com.goldenroadgames.carddrop.permanentstorage"

    @Published private(set) var product: Product?
    @Published private(set) var isPurchased = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    /// Called on the main thread after a successful purchase is verified and written to Supabase.
    var onPurchaseComplete: (() -> Void)?

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
        Task { await loadProduct() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load product from App Store / StoreKit config

    @MainActor
    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.permanentStorageID])
            product = products.first
        } catch {
            errorMessage = "Unable to load product: \(error.localizedDescription)"
        }
    }

    // MARK: - Purchase

    @MainActor
    func purchase() async {
        guard let product else {
            errorMessage = "Product not available."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await unlockPermanentStorage()
                await transaction.finish()
                isPurchased = true
                onPurchaseComplete?()
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Restore

    @MainActor
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        do {
            try await AppStore.sync()
            await checkCurrentEntitlements()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Entitlement check (called on appear / after restore)

    @MainActor
    func checkCurrentEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.permanentStorageID {
                isPurchased = true
                return
            }
        }
    }

    // MARK: - Transaction listener (handles deferred / Ask-to-Buy completions)

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result,
                   transaction.productID == Self.permanentStorageID {
                    await self.unlockPermanentStorage()
                    await transaction.finish()
                    await MainActor.run {
                        self.isPurchased = true
                        self.onPurchaseComplete?()
                    }
                }
            }
        }
    }

    // MARK: - Unlock in Supabase

    private func unlockPermanentStorage() async {
        guard let userID = try? await supabase.auth.session.user.id.uuidString else { return }
        _ = try? await supabase
            .from("users")
            .update(["tier": "unlimited"])
            .eq("id", value: userID)
            .execute()
    }

    // MARK: - Verification helper

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw PurchaseError.failedVerification
        case .verified(let value):
            return value
        }
    }

    enum PurchaseError: Error {
        case failedVerification
    }
}
