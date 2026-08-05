import SwiftUI
import Supabase

/// Upgrades an anonymous session to a named account via email + password.
/// Supabase preserves the user's UUID, so all scoped local data survives automatically.
/// Can be presented as a standalone sheet (from ProfileView) or pushed within a NavigationStack
/// (from AnonymousSignOutView). Pass isStandalone = true for the sheet case.
struct CreateAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager

    var isStandalone: Bool = false

    @State private var firstName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didSucceed = false

    var body: some View {
        Group {
            if isStandalone {
                NavigationStack { content }
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                Text("Create your account")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Your drafts and saved addresses will carry over automatically.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 16)

            if didSucceed {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text("Account created!")
                        .font(.headline)
                    Text("You're now signed in as \(email).")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .transition(.opacity)
            } else {
                VStack(spacing: 12) {
                    TextField("First name", text: $firstName)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.words)

                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: createAccount) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("Create Account")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(Color.brandBlue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .disabled(isLoading || firstName.isEmpty || email.isEmpty || password.isEmpty)
                }
                .padding(.horizontal)
            }

            Spacer()
        }
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isStandalone {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isLoading)
                }
            }
            if didSucceed {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .animation(.easeInOut, value: didSucceed)
    }

    private func createAccount() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await supabase.auth.update(user: UserAttributes(email: email, password: password))
                // Save first name to profile
                authManager.saveProfile(firstName: firstName, street: "", city: "",
                                        state: "", zip: "", country: "")
                didSucceed = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
