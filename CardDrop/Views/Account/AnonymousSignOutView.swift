import SwiftUI

struct AnonymousSignOutView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var draftManager: DraftManager
    @EnvironmentObject var addressBook: AddressBookManager
    @Environment(\.dismiss) private var dismiss

    let namedAccounts: [LocalAccount]
    @State private var isWorking = false
    @State private var showCreateAccount = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {

                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 44))
                            .foregroundColor(.orange)

                        Text("Your work isn't saved")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("If you sign out without an account, your drafts and saved addresses will be lost.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 32)

                    VStack(spacing: 16) {

                        // 1. Save to named accounts
                        if !namedAccounts.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Save to an existing account")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)

                                VStack(spacing: 0) {
                                    ForEach(namedAccounts) { account in
                                        Button {
                                            merge(into: account)
                                        } label: {
                                            HStack {
                                                Image(systemName: "person.circle")
                                                    .foregroundColor(.accentColor)
                                                Text(account.displayName)
                                                    .foregroundColor(.primary)
                                                Spacer()
                                                if isWorking {
                                                    ProgressView().scaleEffect(0.8)
                                                } else {
                                                    Image(systemName: "chevron.right")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .padding()
                                        }
                                        .disabled(isWorking)

                                        if account.id != namedAccounts.last?.id {
                                            Divider().padding(.leading)
                                        }
                                    }
                                }
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                            }
                        }

                        // 2. Save to a new account
                        VStack(alignment: .leading, spacing: 8) {
                            Text(namedAccounts.isEmpty ? "Save your work" : "Or save to a new account")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)

                            Button(action: { authManager.signInWithApple() }) {
                                HStack {
                                    Image(systemName: "apple.logo")
                                    Text("Sign in with Apple")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.primary)
                                .foregroundColor(Color(uiColor: .systemBackground))
                                .cornerRadius(999)
                            }
                            .disabled(isWorking)

                            Button(action: { showCreateAccount = true }) {
                                Text("Create Account with Email")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.brandBlue)
                                    .foregroundColor(.white)
                                    .cornerRadius(999)
                            }
                            .disabled(isWorking)
                        }

                        // 3. Discard
                        Button(role: .destructive) {
                            discard()
                        } label: {
                            Text("Discard and sign out")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .foregroundColor(.red)
                                .cornerRadius(999)
                        }
                        .disabled(isWorking)

                        // 4. Keep working
                        Button("Keep working") {
                            dismiss()
                        }
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .disabled(isWorking)
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 32)
                }
            }
            .navigationTitle("Sign Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem("Cancel", placement: .cancellationAction, isDisabled: isWorking) { dismiss() }
            }
            .navigationDestination(isPresented: $showCreateAccount) {
                CreateAccountView()
            }
        }
    }

    private func merge(into account: LocalAccount) {
        guard let anonymousID = authManager.currentUserID else { return }
        isWorking = true
        draftManager.mergeAnonymousData(from: anonymousID, into: account.userID)
        addressBook.mergeAnonymousData(from: anonymousID, into: account.userID)
        authManager.signOut()
    }

    private func discard() {
        draftManager.clearAllData()
        addressBook.clearAllData()
        authManager.signOut()
    }
}
