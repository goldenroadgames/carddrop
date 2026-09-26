import SwiftUI
import Combine
import Supabase
import AuthenticationServices
import CryptoKit

class AuthManager: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var isAnonymous = false
    @Published var isEmailVerified = false
    @Published var currentUserID: String?
    @Published var currentUserEmail: String?

    // Profile fields — loaded from Supabase on sign-in, cached here
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var profilePhone: String = ""
    @Published var profileStreet: String = ""
    @Published var profileCity: String = ""
    @Published var profileState: String = ""
    @Published var profileZip: String = ""
    @Published var profileCountry: String = ""

    // Marketing-use preference (Privacy Policy Section 5) — defaults true to
    // match the DB column default; only meaningful for non-anonymous users.
    @Published var allowMarketingUse: Bool = true

    // Subscription tier
    @Published private(set) var hasPermanentStorage: Bool = false

    // Send limit proximity
    @Published private(set) var nearMonthlyLimit: Bool = false

    // Sign in with Apple — bridges the ASAuthorizationController delegate
    // callbacks (which can't carry async context) back to the async link flow.
    private var currentAppleNonce: String?
    private var pendingAppleCompletion: (() -> Void)?

    override init() {
        super.init()
        Task { @MainActor in
            // supabase-swift's next major version will emit the locally
            // cached session as `.initialSession` unconditionally, even if
            // it's expired/invalid, and expects callers to check
            // `isExpired` themselves (see supabase/supabase-swift#822).
            // Guarding here now makes us forward-compatible with that
            // change instead of silently treating a stale session as
            // "logged in" once it lands.
            for await (_, rawSession) in supabase.auth.authStateChanges {
                let session = (rawSession?.isExpired == true) ? nil : rawSession
                self.isAuthenticated = session != nil
                self.isAnonymous = session?.user.isAnonymous == true
                self.isEmailVerified = session?.user.isAnonymous == false
                    && session?.user.userMetadata["send_unlocked"] == .bool(true)
                self.currentUserID = session?.user.id.uuidString
                self.currentUserEmail = session?.user.email

                if let session, !session.user.isAnonymous, let email = session.user.email, !email.isEmpty {
                    AccountRegistry.shared.register(userID: session.user.id.uuidString, displayName: email)
                }
                if let session {
                    Task { await self.loadProfile(id: session.user.id) }
                } else {
                    self.clearProfile()
                }
            }
        }
    }

    func signOut() {
        Task {
            try? await supabase.auth.signOut()
        }
    }

    // MARK: - Profile

    func loadProfile(id: UUID) async {
        struct Row: Decodable {
            let first_name: String?
            let last_name: String?
            let phone: String?
            let street: String?
            let city: String?
            let state: String?
            let zip: String?
            let country: String?
            let tier: String?
            let sends_this_month: Int?
            let allow_marketing_use: Bool?
        }
        struct ConfigRow: Decodable { let value: String }
        guard let row = try? await supabase
            .from("users")
            .select("first_name, last_name, phone, street, city, state, zip, country, tier, sends_this_month, allow_marketing_use")
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value as Row
        else { return }

        var nearLimit = false
        if isAnonymous || !isEmailVerified {
            let configKey = isAnonymous ? "send_limit_anonymous_monthly" : "send_limit_unverified_monthly"
            if let configRow = try? await supabase
                .from("zz_config")
                .select("value")
                .eq("key", value: configKey)
                .single()
                .execute()
                .value as ConfigRow,
               let limit = Int(configRow.value), limit > 0,
               let sent = row.sends_this_month {
                nearLimit = sent >= limit - 1
            }
        }

        await MainActor.run {
            // Don't clobber a name already set locally (e.g. from Apple's
            // one-time name grant on first sign-in) before it's persisted.
            if let f = row.first_name, !f.isEmpty { firstName = f }
            lastName             = row.last_name   ?? ""
            profilePhone         = row.phone       ?? ""
            profileStreet        = row.street     ?? ""
            profileCity          = row.city       ?? ""
            profileState         = row.state      ?? ""
            profileZip           = row.zip        ?? ""
            profileCountry       = row.country    ?? ""
            hasPermanentStorage  = row.tier == "unlimited"
            nearMonthlyLimit     = nearLimit
            allowMarketingUse    = row.allow_marketing_use ?? true
        }
    }

    /// Persists the marketing-use opt-out (Privacy Policy Section 5). Only
    /// affects which cards we select going forward — never retracts cards
    /// already flagged for marketing use.
    func setAllowMarketingUse(_ allow: Bool) {
        guard let idString = currentUserID, let id = UUID(uuidString: idString) else { return }
        allowMarketingUse = allow
        Task {
            let row: [String: AnyJSON] = [
                "id": .string(id.uuidString),
                "allow_marketing_use": .bool(allow)
            ]
            _ = try? await supabase.from("users").upsert(row, onConflict: "id").execute()
        }
    }

    /// Called after a successful IAP purchase to immediately reflect the upgrade in-app.
    func setTierUnlimited() {
        hasPermanentStorage = true
    }

    func saveProfile(firstName: String, lastName: String = "", phone: String = "", street: String,
                     city: String, state: String, zip: String, country: String) {
        guard let idString = currentUserID, let id = UUID(uuidString: idString) else { return }
        self.firstName      = firstName
        self.lastName       = lastName
        self.profilePhone   = phone
        self.profileStreet  = street
        self.profileCity    = city
        self.profileState   = state
        self.profileZip     = zip
        self.profileCountry = country
        Task {
            let row: [String: AnyJSON] = [
                "id":         .string(id.uuidString),
                "first_name": .string(firstName),
                "last_name":  .string(lastName),
                "phone":      .string(phone),
                "street":     .string(street),
                "city":       .string(city),
                "state":      .string(state),
                "zip":        .string(zip),
                "country":    .string(country)
            ]
            _ = try? await supabase.from("users").upsert(row, onConflict: "id").execute()

            // Also keep user_address_book's "profile" row in sync — that's
            // what the physical-mail send flow's sender picker reads to
            // prefill a default return address (see
            // project_lob_integration_progress). The users-table columns
            // above are legacy/unrelated to that flow.
            guard !street.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let profileAddress = SavedMailingAddress(
                id: UUID(),
                nickname: nil,
                firstName: firstName.isEmpty ? nil : firstName,
                lastName: lastName.isEmpty ? nil : lastName,
                street: street,
                city: city,
                state: state,
                zip: zip,
                country: country.isEmpty ? "US" : country,
                email: nil,
                phone: phone.isEmpty ? nil : phone,
                addressType: .profile,
                isVerified: false,
                verifiedAt: nil,
                lobVerificationID: nil,
                lastUsedAt: Date()
            )
            if let saved = try? await AddressBookService.save(profileAddress, existing: nil), !saved.isVerified {
                _ = try? await AddressBookService.verify(id: saved.id)
            }
        }
    }

    private func clearProfile() {
        firstName = ""; lastName = ""; profilePhone = ""; profileStreet = ""; profileCity = ""
        profileState = ""; profileZip = ""; profileCountry = ""
        hasPermanentStorage = false
        nearMonthlyLimit = false
        allowMarketingUse = true
    }

    // MARK: - Email

    /// Sends (or resends) the confirmation email for the current user's email address.
    /// Uses an Edge Function backed by the Admin API — more reliable than auth.resend()
    /// which doesn't always route through custom SMTP.
    func resendConfirmationEmail(to explicitEmail: String? = nil) {
        guard let email = explicitEmail ?? currentUserEmail else { return }
        Task {
            do {
                let _: Void = try await supabase.functions.invoke(
                    "resend-confirmation",
                    options: FunctionInvokeOptions(body: ["email": email])
                )
                print("✅ Resend confirmation sent to \(email)")
            } catch {
                print("❌ Resend confirmation failed: \(error)")
            }
        }
    }

    /// Updates the email address on the account. Supabase sends a confirmation to the new address.
    /// The UUID and all associated content are unaffected.
    func changeEmail(to newEmail: String) async throws {
        try await supabase.auth.update(user: UserAttributes(email: newEmail))
        await MainActor.run { currentUserEmail = newEmail }
    }

    /// Refreshes the session from Supabase — picks up email verification done in a browser.
    func refreshSession() {
        Task {
            try? await supabase.auth.refreshSession()
        }
    }

    func refreshSessionAsync() async {
        try? await supabase.auth.refreshSession()
    }

    // MARK: - OTP Verification

    /// Sends a 6-digit OTP code to the user's existing email for verification.
    /// Requires "Email OTP" enabled in Supabase → Authentication → Providers → Email.
    func sendVerificationOTP(to explicitEmail: String? = nil) {
        guard let email = explicitEmail ?? currentUserEmail else { return }
        Task {
            try? await supabase.auth.signInWithOTP(email: email, shouldCreateUser: false)
        }
    }

    /// Sends a 6-digit OTP to a new email address, creating a fresh account.
    /// Used when an unverified user corrects a fat-fingered email.
    func sendOTPForNewAccount(_ email: String) {
        Task {
            try? await supabase.auth.signInWithOTP(email: email, shouldCreateUser: true)
        }
    }

    /// Returns the current session's user ID directly from Supabase.
    /// More reliable than currentUserID immediately after a session swap.
    func getCurrentSessionUserID() async -> String? {
        return try? await supabase.auth.session.user.id.uuidString
    }

    /// Verifies the OTP code the user entered. On success sets send_unlocked = true.
    func verifyOTP(email: String, code: String) async throws {
        try await supabase.auth.verifyOTP(email: email, token: code, type: .email)
        try await supabase.auth.update(user: UserAttributes(data: ["send_unlocked": .bool(true)]))
    }

    /// Called when user taps "I've verified my email". Refreshes the session to
    /// pick up send_unlocked if it was set via the email link on this device.
    func unlockSendingIfVerified() {
        Task {
            try? await supabase.auth.refreshSession()
        }
    }

    /// Call at feature gates that require a verified email.
    /// Returns true if verified, triggers a resend and returns false if not.
    func requireEmailVerification() -> Bool {
        if isEmailVerified { return true }
        resendConfirmationEmail()
        return false
    }

    /// Sign in with Apple — links onto the current anonymous session via
    /// Supabase's native linkIdentityWithIdToken, preserving the anonymous
    /// UUID (and any draft data tied to it). An anonymous session always
    /// exists by the time this is reachable (AuthManager.init ensures one
    /// at launch), but we guard here too in case that hasn't resolved yet.
    func signInWithApple(onSuccess: (() -> Void)? = nil) {
        pendingAppleCompletion = onSuccess
        Task { @MainActor in
            if !isAnonymous {
                try? await supabase.auth.signInAnonymously()
            }

            let nonce = Self.randomNonceString()
            currentAppleNonce = nonce

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private static func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(status == errSecSuccess, "Unable to generate nonce: OSStatus \(status)")
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthManager: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let nonce = currentAppleNonce
        else {
            print("❌ Sign in with Apple: missing credential/idToken/nonce")
            return
        }
        currentAppleNonce = nil
        let givenName = credential.fullName?.givenName
        let completion = pendingAppleCompletion
        pendingAppleCompletion = nil

        Task { @MainActor in
            let credentials = OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            do {
                // First-ever Apple sign-in for this device/anonymous session:
                // link onto the current anonymous user so drafts carry over.
                try await supabase.auth.linkIdentityWithIdToken(credentials: credentials)
            } catch {
                // Fails when this Apple identity is already linked to a
                // DIFFERENT Supabase user — the expected case for a
                // returning user signing back in after signOut(), since
                // signOut leaves a brand-new (different) anonymous session
                // in its place, and that identity can't be linked twice.
                // Fall back to a normal sign-in, which looks up and resumes
                // the existing Apple-linked account instead.
                do {
                    try await supabase.auth.signInWithIdToken(credentials: credentials)
                } catch {
                    print("❌ Sign in with Apple failed (both link and sign-in): \(error)")
                    return
                }
            }
            try? await supabase.auth.update(user: UserAttributes(data: ["send_unlocked": .bool(true)]))
            // Apple only grants the name on the very first authorization for
            // this app — capture it now, it won't come again.
            if let givenName, !givenName.isEmpty {
                self.firstName = givenName
            }
            completion?()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        currentAppleNonce = nil
        pendingAppleCompletion = nil
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            return // user backed out — not a real error
        }
        print("❌ Sign in with Apple authorization failed: \(error)")
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
