import SwiftUI

struct ChangeEmailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager

    @State private var newEmail = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didSend = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                        .padding(.top, 16)
                    Text("Change Email Address")
                        .font(.title2.weight(.semibold))
                    Text("We'll send a verification link to your new address. Your account and content stay put.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                if didSend {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("Check your inbox")
                            .font(.headline)
                        Text("A verification link was sent to \(newEmail).\nYour address will update once you confirm it.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .transition(.opacity)
                } else {
                    VStack(spacing: 12) {
                        TextField("New email address", text: $newEmail)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }

                        Button(action: submit) {
                            if isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            } else {
                                Text("Send Verification Link")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                        }
                        .background(Color.brandBlue)
                        .foregroundColor(.white)
                        .cornerRadius(999)
                        .disabled(isLoading || newEmail.isEmpty)
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .animation(.easeInOut, value: didSend)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem("Cancel", placement: .cancellationAction, isDisabled: isLoading) { dismiss() }
                if didSend {
                    toolbarPillItem("Done", placement: .confirmationAction, emphasis: .primary) { dismiss() }
                }
            }
        }
    }

    private func submit() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authManager.changeEmail(to: newEmail)
                didSend = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
