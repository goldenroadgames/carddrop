import SwiftUI
import Supabase

/// Presented when a user taps "Next: Send" without a verified email.
/// Handles three states:
///   1. Anonymous — create an account (Apple or email+password) and collect profile
///   2. Named but unverified — prompt to check inbox, offer resend / change email
///   3. Verified — calls onSuccess() immediately (shouldn't normally be shown)
struct SubscribeGateView: View {
    var onSuccess: () -> Void

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var draftManager: DraftManager
    @EnvironmentObject private var addressBook: AddressBookManager
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var showEmailSignup = false
    @State private var showAppleProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if authManager.isEmailVerified || !authManager.isAnonymous {
                        // Verified or non-anonymous — shouldn't normally be shown here
                        Color.clear.onAppear { onSuccess() }

                    } else {
                        anonymousContent
                    }
                }
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem("Cancel", placement: .cancellationAction, style: .bare) { dismiss() }
            }
            .sheet(isPresented: $showEmailSignup) {
                EmailSignupView(onSuccess: onSuccess)
                    .environmentObject(authManager)
                    .environmentObject(draftManager)
                    .environmentObject(addressBook)
            }
            .sheet(isPresented: $showAppleProfile) {
                AppleSignInProfileView(onSuccess: onSuccess)
                    .environmentObject(authManager)
            }
            // Auto-advance when verification comes through
            .onChange(of: authManager.isEmailVerified) {
                if authManager.isEmailVerified { onSuccess() }
            }
        }
        .dynamicTypeSize(.medium ... .xxxLarge)
    }

    // MARK: - Anonymous: create account

    private var anonymousContent: some View {
        VStack(spacing: 24) {
            // Hero
            VStack(spacing: 0) {
                CardDropWordmark()
                    .padding(.top, 5)
                Text("Create a free account")
                    .font(.title3.weight(.bold))
                    .padding(.top, 20)
            }

            // Benefits
            VStack(alignment: .leading, spacing: 10) {
                benefitRow("envelope.fill",      .blue,   "Email animated postcards — free")
                benefitRow("message.fill",        .green,  "Message postcards — free")
                HStack(spacing: 12) {
                    PostcardIconView()
                        .frame(width: 31, height: 31)
                        .background(Color.purple)
                        .cornerRadius(7)
                    Text("Real Postcards — just pay per card")
                        .font(.subheadline)
                    Spacer()
                }
            }
            .padding(.leading, 27)
            .padding(.trailing, 32)

            Divider().padding(.horizontal)

            VStack(spacing: 5) {
                // TODO: Replace with real Apple auth when Apple Developer is configured.
                // On successful auth, Apple provides name (first login only) — store to
                // authManager before presenting AppleSignInProfileView.
                Button(action: { authManager.signInWithApple() }) {
                    HStack {
                        Image(systemName: "apple.logo")
                        Text("Sign in with Apple")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.primary)
                    .foregroundColor(Color(uiColor: .systemBackground))
                    .cornerRadius(999)
                }

                Button(action: { showEmailSignup = true }) {
                    Text("Sign in with Email")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.brandBlue)
                        .foregroundColor(.white)
                        .cornerRadius(999)
                }
            }
            .padding(.horizontal)

            privacyNote
        }
    }

    // MARK: - Helpers

    private var privacyNote: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.subheadline)
                Text("Your privacy matters")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)

            Text("We store your name, email, and optional address and phone to auto-fill your cards and deliver physical ones when you choose. Recipient names and addresses you enter are saved to your personal address book so you don't have to re-enter them — we don't use recipient information for marketing or share it with anyone. You can delete your own info or any saved address at any time, no questions asked.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func benefitRow(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.white)
                .frame(width: 31, height: 31)
                .background(color)
                .cornerRadius(7)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }

}

// MARK: - Email Auth Sheet (sign-in + sign-up unified)

struct EmailSignupView: View {
    var onSuccess: () -> Void

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var draftManager: DraftManager
    @EnvironmentObject private var addressBook: AddressBookManager
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private enum Phase { case initial, wrongPassword, resetSent }
    @State private var phase: Phase = .initial

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text(phase == .resetSent ? "Check Your Inbox" : "Sign In")
                            .font(.title2.weight(.bold))
                            .padding(.top, 8)
                        if phase != .resetSent {
                            Text("Free to join. No subscription required.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    VStack(spacing: 10) {
                        TextField("Email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .disabled(phase != .initial)

                        if phase != .resetSent {
                            ZStack(alignment: .trailing) {
                                if showPassword {
                                    TextField("Password", text: $password)
                                        .textFieldStyle(.roundedBorder)
                                        .autocapitalization(.none)
                                        .autocorrectionDisabled()
                                } else {
                                    SecureField("Password", text: $password)
                                        .textFieldStyle(.roundedBorder)
                                }
                                Button(action: { showPassword.toggle() }) {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundColor(.secondary)
                                        .padding(.trailing, 8)
                                }
                            }
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }

                        switch phase {
                        case .initial:
                            mainButton("Sign In", action: attemptSignIn)
                                .disabled(email.isEmpty || password.isEmpty)

                        case .wrongPassword:
                            Text("Incorrect password.")
                                .font(.caption).foregroundColor(.secondary)
                            mainButton("Sign In", action: attemptSignIn)
                                .disabled(email.isEmpty || password.isEmpty)
                            Button("Send password reset link", action: sendReset)
                                .font(.subheadline).foregroundColor(.secondary)
                                .disabled(isLoading)

                        case .resetSent:
                            Text("Reset link sent — check your inbox.")
                                .font(.subheadline).foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal)
                    .animation(.easeInOut(duration: 0.2), value: phase)
                }
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem("Cancel", placement: .cancellationAction, style: .bare, isDisabled: isLoading) { dismiss() }
            }
            .onChange(of: authManager.isEmailVerified) {
                if authManager.isEmailVerified { onSuccess() }
            }
        }
        .dynamicTypeSize(.medium ... .xxxLarge)
    }

    // MARK: - Actions

    private func attemptSignIn() {
        isLoading = true
        errorMessage = nil
        let anonIDBeforeSignIn = authManager.currentUserID
        Task {
            defer { isLoading = false }
            do {
                try await supabase.auth.signIn(email: email, password: password)
                let newID = try? await supabase.auth.session.user.id.uuidString
                if let anonID = anonIDBeforeSignIn, let newID, anonID != newID {
                    draftManager.mergeAnonymousData(from: anonID, into: newID)
                    addressBook.mergeAnonymousData(from: anonID, into: newID)
                    draftManager.setUser(newID)
                    addressBook.setUser(newID)
                }
                onSuccess()
            } catch {
                let isKnown = AccountRegistry.shared.all()
                    .contains { $0.displayName.lowercased() == email.lowercased() }
                if isKnown {
                    withAnimation { phase = .wrongPassword }
                } else {
                    await createAccount()
                }
            }
        }
    }

    private func createAccount() async {
        do {
            try await supabase.auth.update(user: UserAttributes(email: email, password: password))
            if let id = try? await supabase.auth.session.user.id.uuidString {
                try? await supabase
                    .from("users")
                    .update(["sends_this_month": 0])
                    .eq("id", value: id)
                    .execute()
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendReset() {
        Task {
            try? await supabase.auth.resetPasswordForEmail(email)
            withAnimation { phase = .resetSent }
        }
    }

    @ViewBuilder
    private func mainButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 14)
            } else {
                Text(label)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
        }
        .background(Color.brandBlue)
        .foregroundColor(.white)
        .cornerRadius(999)
        .disabled(isLoading)
    }
}

// MARK: - Apple Sign-In Profile Sheet

/// Presented after successful Sign in with Apple to confirm name and collect mailing address.
/// Apple provides name on first login only — pre-filled from authManager.firstName if available.
/// TODO: Wire onSuccess into the real Apple auth completion callback when Apple Developer is configured.
struct AppleSignInProfileView: View {
    var onSuccess: () -> Void

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var street = ""
    @State private var city = ""
    @State private var stateField = ""
    @State private var zip = ""
    @State private var country = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        CardDropWordmark()
                            .padding(.top, 8)
                        Text("Welcome!")
                            .font(.title2.weight(.bold))
                            .padding(.top, 20)
                        Text("Confirm your name and optionally add your mailing address — it auto-fills as the return address on every card.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    VStack(spacing: 10) {
                        TextField("First name", text: $firstName)
                            .textFieldStyle(.roundedBorder)

                        Text("Optional")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)

                        TextField("Street address", text: $street)
                            .textFieldStyle(.roundedBorder)
                        HStack(spacing: 8) {
                            TextField("City", text: $city)
                                .textFieldStyle(.roundedBorder)
                            TextField("ST", text: $stateField)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 52)
                            TextField("ZIP", text: $zip)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .keyboardType(.numbersAndPunctuation)
                        }
                        TextField("Country", text: $country)
                            .textFieldStyle(.roundedBorder)

                        Button(action: save) {
                            Text("Continue")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .background(Color.brandBlue)
                        .foregroundColor(.white)
                        .cornerRadius(999)
                        .disabled(firstName.isEmpty)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem("Skip", placement: .cancellationAction) { onSuccess(); dismiss() }
            }
            .onAppear {
                firstName = authManager.firstName
            }
        }
        .dynamicTypeSize(.medium ... .xxxLarge)
    }

    private func save() {
        authManager.saveProfile(firstName: firstName, street: street, city: city,
                                state: stateField, zip: zip, country: country)
        onSuccess()
        dismiss()
    }
}

// MARK: - Postcard Icon

struct PostcardIconView: View {
    var body: some View {
        Canvas { ctx, size in
            let lw: CGFloat = 1.5
            let purple = Color.purple

            // Postcard shape: landscape, centered in the square (like envelope proportions)
            let cardW: CGFloat = size.width - 8
            let cardH: CGFloat = cardW * 0.76
            let originX = (size.width - cardW) / 2
            let originY = (size.height - cardH) / 2
            let divX = originX + cardW * 0.58

            let outerRect = CGRect(x: originX, y: originY, width: cardW, height: cardH)

            // White filled postcard body
            ctx.fill(Path(roundedRect: outerRect, cornerRadius: 2.5), with: .color(.white))

            // Purple border
            ctx.stroke(Path(roundedRect: outerRect, cornerRadius: 2.5), with: .color(purple), lineWidth: lw)

            // Purple vertical divider
            var divPath = Path()
            divPath.move(to: CGPoint(x: divX, y: originY))
            divPath.addLine(to: CGPoint(x: divX, y: originY + cardH))
            ctx.stroke(divPath, with: .color(purple), lineWidth: lw)

            // Purple stamp square (top-right quadrant)
            let stampW: CGFloat = cardW * 0.15
            let stampH: CGFloat = stampW
            let stampX = divX + (originX + cardW - divX - stampW) / 2
            let stampRect = CGRect(x: stampX, y: originY + cardH * 0.20, width: stampW, height: stampH)
            ctx.fill(Path(roundedRect: stampRect, cornerRadius: 1), with: .color(purple))

            // Purple address lines (left side)
            let lineStartX = originX + 2.5
            let lineEndX = divX - 3
            for lineY in [originY + cardH * 0.35, originY + cardH * 0.55, originY + cardH * 0.75] {
                var linePath = Path()
                linePath.move(to: CGPoint(x: lineStartX, y: lineY))
                linePath.addLine(to: CGPoint(x: lineEndX, y: lineY))
                ctx.stroke(linePath, with: .color(purple), lineWidth: lw)
            }
        }
    }
}
