import SwiftUI

/// Single canonical overlay for email OTP verification.
/// Auto-sends a code on first appearance. Dismissing without verifying is always safe —
/// callers decide what happens next (stay on send screen, open account tab, etc.).
struct OTPVerificationView: View {
    var onSuccess: () -> Void = {}
    var onCancel: () -> Void = {}

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var draftManager: DraftManager
    @EnvironmentObject var addressBook: AddressBookManager
    @Environment(\.dismiss) private var dismiss

    @State private var otpEmail = ""
    @State private var previousUserID: String? = nil
    @State private var otpCode = ""
    @State private var otpSent = false
    @State private var otpError: String?
    @State private var isVerifying = false
    @State private var showCorrectEmail = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.orange)
                            .padding(.top, 32)
                        Text("Verify Your Email")
                            .font(.title2.weight(.bold))
                        Text(otpEmail)
                            .font(.subheadline)
                        Text("Enter the 6-digit code we emailed you.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .multilineTextAlignment(.center)

                    // OTP entry
                    VStack(spacing: 12) {
                        if otpSent {
                            TextField("6-digit code", text: $otpCode)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .font(.title3.monospacedDigit())

                            if let error = otpError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }

                            Button(action: verifyCode) {
                                if isVerifying {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                } else {
                                    Text("Verify")
                                        .font(.system(size: 17, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                }
                            }
                            .background(Color.brandBlue)
                            .foregroundColor(.white)
                            .cornerRadius(999)
                            .disabled(otpCode.count < 6 || isVerifying)

                            Button("Resend code") { sendCode() }
                                .font(.subheadline)
                                .foregroundColor(.accentColor)
                        } else {
                            Button(action: sendCode) {
                                Text("Send Code")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.brandBlue)
                                    .foregroundColor(.white)
                                    .cornerRadius(999)
                            }
                        }

                        Button("Wrong email? Change it") {
                            showCorrectEmail = true
                        }
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal)

                    Text("This will close automatically once verified.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem("Cancel", placement: .cancellationAction) { onCancel(); dismiss() }
            }
            .onAppear {
                otpEmail = authManager.currentUserEmail ?? ""
                if !otpSent { sendCode() }
            }
            .onChange(of: authManager.isEmailVerified) {
                if authManager.isEmailVerified {
                    onSuccess()
                    dismiss()
                }
            }
            .sheet(isPresented: $showCorrectEmail) {
                CorrectEmailView(currentEmail: otpEmail) { newEmail in
                    previousUserID = authManager.currentUserID
                    otpEmail = newEmail
                    otpCode = ""
                    otpError = nil
                    otpSent = true
                    authManager.sendOTPForNewAccount(newEmail)
                }
            }
        }
        .dynamicTypeSize(.medium ... .xxxLarge)
    }

    private func sendCode() {
        guard !otpEmail.isEmpty else { return }
        authManager.sendVerificationOTP(to: otpEmail)
        otpSent = true
        otpCode = ""
        otpError = nil
    }

    private func verifyCode() {
        guard !otpEmail.isEmpty else { return }
        isVerifying = true
        otpError = nil
        let oldID = previousUserID
        Task {
            do {
                try await authManager.verifyOTP(email: otpEmail, code: otpCode)
                if let oldID, let newID = await authManager.getCurrentSessionUserID(), oldID != newID {
                    draftManager.mergeAnonymousData(from: oldID, into: newID)
                    addressBook.mergeAnonymousData(from: oldID, into: newID)
                    draftManager.setUser(newID)
                    addressBook.setUser(newID)
                }
            } catch {
                otpError = "Incorrect code. Please try again."
            }
            isVerifying = false
        }
    }
}

// MARK: - Correct Email Sheet

struct CorrectEmailView: View {
    let currentEmail: String
    var onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newEmail = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.orange)
                        .padding(.top, 32)
                    Text("Correct Your Email")
                        .font(.title2.weight(.bold))
                    Text("Enter the correct address. We'll send a new code immediately.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    TextField("New email address", text: $newEmail)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .font(.body)

                    Button(action: confirm) {
                        Text("Update and Verify")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.brandBlue)
                            .foregroundColor(.white)
                            .cornerRadius(999)
                    }
                    .disabled(newEmail.isEmpty || newEmail == currentEmail)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem("Cancel", placement: .cancellationAction) { dismiss() }
            }
        }
        .dynamicTypeSize(.medium ... .xxxLarge)
    }

    private func confirm() {
        onConfirm(newEmail)
        dismiss()
    }
}
