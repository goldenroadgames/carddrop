import SwiftUI
import Supabase

struct AuthView: View {
    var onSkip: (() -> Void)? = nil
    @EnvironmentObject var authManager: AuthManager

    @State private var showEmailSignIn = false
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                CardDropWordmark()
                Text("The OG Personal Messenger")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: { authManager.signInWithApple() }) {
                    HStack {
                        Image(systemName: "apple.logo")
                        Text("Sign in with Apple")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.primary)
                    .foregroundColor(Color(uiColor: .systemBackground))
                    .cornerRadius(12)
                }

                Button(action: { showEmailSignIn = true }) {
                    Text("Sign in with Email")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandBlue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button(action: handleAnonymousSignIn) {
                    if isLoading {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text("Continue without signing in")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
                .disabled(isLoading)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .sheet(isPresented: $showEmailSignIn) {
            EmailSignupView(onSuccess: {})
        }
    }

    private func handleAnonymousSignIn() {
        if authManager.isAnonymous {
            onSkip?()
        } else {
            isLoading = true
            Task {
                do {
                    try await supabase.auth.signInAnonymously()
                    onSkip?()
                } catch {
                    print("❌ signInAnonymously failed: \(error)")
                }
                isLoading = false
            }
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthManager())
}
