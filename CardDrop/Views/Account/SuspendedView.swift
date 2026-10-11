import SwiftUI

/// Shown instead of the whole app when the account or device is suspended.
/// A suspended user can still delete their account (App Store 5.1.1(v) and
/// privacy law still apply).
struct SuspendedView: View {
    @State private var showLegal: LegalDocumentService.Document?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("Account Suspended")
                .font(.title2.weight(.semibold))
            Text("Your account has been suspended because of complaints about cards you sent.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Text("If you have questions, contact support@carddropapp.com.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            if let url = URL(string: "mailto:support@carddropapp.com") {
                Link("Email Support", destination: url)
                    .font(.body.weight(.semibold))
            }
            DeleteAccountButton()
                .font(.body)
                .padding(.top, 8)
            Spacer()
            HStack(spacing: 4) {
                Button("Terms of Service") { showLegal = .termsOfService }
                Text("·")
                Button("Privacy Policy") { showLegal = .privacyPolicy }
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $showLegal) { document in
            NavigationStack {
                LegalDocumentView(
                    title: document == .termsOfService ? "Terms of Service" : "Privacy Policy",
                    document: document
                )
                .toolbar {
                    toolbarPillItem("Done", placement: .confirmationAction, style: .bare) { showLegal = nil }
                }
            }
        }
    }
}
