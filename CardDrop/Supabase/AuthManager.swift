import SwiftUI
import Combine
import Supabase

class AuthManager: ObservableObject {
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

    // Subscription tier
    @Published private(set) var hasPermanentStorage: Bool = false

    // Send limit proximity
    @Published private(set) var nearMonthlyLimit: Bool = false

    init() {
        Task { @MainActor in
            for await (_, session) in supabase.auth.authStateChanges {
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
        }
        struct ConfigRow: Decodable { let value: String }
        guard let row = try? await supabase
            .from("users")
            .select("first_name, last_name, phone, street, city, state, zip, country, tier, sends_this_month")
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value as Row
        else { return }

        var nearLimit = false
        if isAnonymous || !isEmailVerified {
            let configKey = isAnonymous ? "send_limit_anonymous_monthly" : "send_limit_unverified_monthly"
            if let configRow = try? await supabase
                .from("config")
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
            firstName            = row.first_name  ?? ""
            lastName             = row.last_name   ?? ""
            profilePhone         = row.phone       ?? ""
            profileStreet        = row.street     ?? ""
            profileCity          = row.city       ?? ""
            profileState         = row.state      ?? ""
            profileZip           = row.zip        ?? ""
            profileCountry       = row.country    ?? ""
            hasPermanentStorage  = row.tier == "unlimited"
            nearMonthlyLimit     = nearLimit
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
        }
    }

    private func clearProfile() {
        firstName = ""; lastName = ""; profilePhone = ""; profileStreet = ""; profileCity = ""
        profileState = ""; profileZip = ""; profileCountry = ""
        hasPermanentStorage = false
        nearMonthlyLimit = false
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

    /// Sign in with Apple — preserves anonymous UUID via Supabase linkIdentity.
    /// TODO: implement once Apple Developer + Supabase Apple provider are configured.
    func signInWithApple() {
        // Implementation pending Apple Developer setup
    }
}
