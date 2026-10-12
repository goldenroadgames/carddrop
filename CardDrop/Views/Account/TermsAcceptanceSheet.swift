import SwiftUI

// Shown once before a person's first send (and again only if the Terms are
// changed materially). Agreeing records the date and version on the server.
struct TermsAcceptanceSheet: View {
    let onAgree: () -> Void
    let onCancel: () -> Void

    @State private var agreed = false
    @State private var saving = false
    @State private var errorText: String?
    @State private var showLegal: LegalDocumentService.Document?

    var body: some View {
        VStack(spacing: 18) {
            Text("Before You Send")
                .font(.title2.weight(.semibold))
                .padding(.top, 24)

            Text("CardDrop is for sharing happy moments. Please don't use it to send anything illegal, sexual, violent, or harassing.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                agreed.toggle()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: agreed ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundColor(agreed ? .brandBlue : .secondary)
                    Text("I agree to the Terms of Service and Privacy Policy, and I won't use CardDrop to send illegal, sexual, violent, or harassing content.")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Button("Terms of Service") { showLegal = .termsOfService }
                Text("·")
                Button("Privacy Policy") { showLegal = .privacyPolicy }
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)

            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await agree() }
            } label: {
                Group {
                    if saving { ProgressView().tint(.white) }
                    else { Text("I Agree - Let's Go").fontWeight(.semibold) }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.brandBlue.opacity(agreed ? 1 : 0.35))
                .clipShape(Capsule())
            }
            .disabled(!agreed || saving)

            Button("Cancel", action: onCancel)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .disabled(saving)

            Text("Have fun CardDropping!")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.brandBlue)
                .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .presentationDetents([.large])
        .interactiveDismissDisabled(saving)
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

    private func agree() async {
        saving = true
        errorText = nil
        do {
            try await TermsService.accept()
            saving = false
            onAgree()
        } catch {
            saving = false
            errorText = "Couldn't save your agreement. Please check your connection and try again."
        }
    }
}
