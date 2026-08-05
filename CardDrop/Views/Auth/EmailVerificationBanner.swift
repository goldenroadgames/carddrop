import SwiftUI

/// Shown persistently at the top of the app when a named account's email is unverified.
/// Non-blocking — user can dismiss per session and keep using the app.
struct EmailVerificationBanner: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var isDismissed = false
    @State private var didResend = false

    var body: some View {
        if !isDismissed {
            HStack(spacing: 12) {
                Image(systemName: "envelope.badge")
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Verify your email")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text(didResend ? "Sent! Check your inbox." : "Check your inbox for a confirmation link.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }

                Spacer()

                if !didResend {
                    Button("Resend") {
                        authManager.resendConfirmationEmail()
                        didResend = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            didResend = false
                        }
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.25))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }

                Button {
                    withAnimation { isDismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(red: 0.85, green: 0.55, blue: 0.05))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
