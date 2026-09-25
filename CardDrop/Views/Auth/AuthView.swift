import SwiftUI
import Supabase

struct AuthView: View {
    var onSkip: (() -> Void)? = nil
    @EnvironmentObject var authManager: AuthManager

    @State private var showEmailSignIn = false
    @State private var isLoading = false
    @State private var isBootstrappingEmailSignIn = false
    // Measured from the actual "Sign in with Apple" pill so the landing
    // animation's bottom padding matches a real pill's height.
    @State private var pillHeight: CGFloat = 54
    // Fetched from the public "carousel_postcards" Supabase Storage bucket —
    // not hardcoded, since Supabase assigns its own object names on upload.
    @State private var sampleImageNames: [String] = []
    // Bundled in Assets.xcassets so the carousel always has content from the
    // very first frame, regardless of network conditions — add image sets
    // with these exact names to Assets.xcassets (drag the jpgs into the
    // asset catalog in Xcode; each becomes its own Image Set named after the
    // file). The Supabase bucket images above are appended after these once
    // fetched, not a replacement for them.
    private let stockImageNames = ["landing_stock_1", "landing_stock_2", "landing_stock_3"]

    var body: some View {
        LandingBrandAnimation(
            description: "Free digital postcards in seconds\nPrint and mail to make it real",
            stockImageNames: stockImageNames,
            sampleImageNames: sampleImageNames,
            pillHeight: pillHeight
        ) {
            VStack(spacing: 6) {
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
                    .background(
                        GeometryReader { g in
                            Color.clear.onAppear { pillHeight = g.size.height }
                        }
                    )
                }

                Button(action: handleEmailSignInTapped) {
                    if isBootstrappingEmailSignIn {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Sign in with Email")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .background(Color.brandBlue)
                .foregroundColor(.white)
                .cornerRadius(999)
                .disabled(isBootstrappingEmailSignIn)

                Button(action: handleAnonymousSignIn) {
                    if isLoading {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text("Continue without signing in")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
                .padding(.top, 14)
                .disabled(isLoading)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            do {
                let files = try await supabase.storage.from("carousel_postcards").list()
                sampleImageNames = files
                    .map(\.name)
                    .filter { !$0.hasPrefix(".") }   // Supabase can create a hidden .emptyFolderPlaceholder entry
            } catch {
                print("❌ failed to list carousel_postcards: \(error)")
            }
        }
        .sheet(isPresented: $showEmailSignIn) {
            EmailSignupView(onSuccess: {})
        }
    }

    // supabase.auth.update(user:) (called by EmailSignupView.createAccount())
    // requires an existing session to attach the email/password to — it
    // throws AuthError.sessionMissing rather than creating one, so a
    // genuinely first-time user (never anonymously signed in) tapping
    // straight into email signup here would hit that error. Ensure an
    // anonymous session exists first, same as "Continue without signing
    // in" already does, before ever showing the email form.
    private func handleEmailSignInTapped() {
        if authManager.isAnonymous {
            showEmailSignIn = true
        } else {
            isBootstrappingEmailSignIn = true
            Task {
                do {
                    try await supabase.auth.signInAnonymously()
                    showEmailSignIn = true
                } catch {
                    print("❌ signInAnonymously (for email signup) failed: \(error)")
                }
                isBootstrappingEmailSignIn = false
            }
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
