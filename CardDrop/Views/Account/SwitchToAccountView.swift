import SwiftUI
import Supabase

/// Signs in to any existing account (on-device or from another device) and merges
/// the current anonymous local data into that account's folder.
/// Order: authenticate first → merge on success → reload managers.
struct SwitchToAccountView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var draftManager: DraftManager
    @EnvironmentObject var addressBook: AddressBookManager
    @Environment(\.dismiss) private var dismiss

    let email: String
    let anonymousUserID: String

    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "person.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    Text("Welcome back")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Enter your password to sign in as\n\(email)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                VStack(spacing: 12) {
                    HStack {
                        Text(email)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: signInThenMerge) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("Sign In")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(Color.brandBlue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .disabled(isLoading || password.isEmpty)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isLoading)
                }
            }
        }
    }

    private func signInThenMerge() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                // 1. Authenticate
                try await supabase.auth.signIn(email: email, password: password)

                // 2. Get the authenticated user's UUID
                guard let targetUserID = authManager.currentUserID else { return }

                // 3. Merge anonymous local data into this account's folder
                draftManager.mergeAnonymousData(from: anonymousUserID, into: targetUserID)
                addressBook.mergeAnonymousData(from: anonymousUserID, into: targetUserID)

                // 4. Reload managers from the merged folder
                draftManager.setUser(targetUserID)
                addressBook.setUser(targetUserID)

            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
