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

    // Laid out like the send options screen: grouped background, a rounded
    // grouped card of rows, a blue 17-pt semibold heading and a full-width
    // capsule button.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    CardDropWordmark()
                        .padding(.top, 5)

                    Text("Ready to send?")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.brandBlue)

                    Text("CardDrop is for sharing happy moments. Send something that will make someone smile.")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.brandBlue)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 4)

                    VStack(spacing: 0) {
                        Button {
                            agreed.toggle()
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: agreed ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 22))
                                    .foregroundColor(agreed ? .brandBlue : .secondary)
                                    .frame(width: 36)
                                Text("I agree to the Terms of Service and Privacy Policy, and I won't use CardDrop to send illegal, sexually explicit, violent, or harassing content.")
                                    .font(.system(size: 17))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)

                        Divider().padding(.leading, 66)
                        legalRow("Terms of Service", .termsOfService)
                        Divider().padding(.leading, 66)
                        legalRow("Privacy Policy", .privacyPolicy)
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)

                    Text("We only ask this of first-time senders, and again when we make changes to our terms.")
                        .font(.system(size: 15))
                        .foregroundColor(.brandBlue)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, -6)
                        .padding(.bottom, 20)

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 17))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Button {
                        Task { await agree() }
                    } label: {
                        Group {
                            if saving { ProgressView().tint(.white) }
                            else { Text("I Agree - Let's Go").font(.system(size: 17, weight: .semibold)) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.brandBlue.opacity(agreed ? 1 : 0.35))
                        .foregroundColor(.white)
                        .cornerRadius(999)
                    }
                    .disabled(!agreed || saving)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Text("Have fun CardDropping!")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.brandBlue)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem("Cancel", placement: .cancellationAction, style: .bare, isDisabled: saving) { onCancel() }
            }
        }
        .dynamicTypeSize(.medium ... .xxxLarge)
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

    // A tappable row that opens one of the documents, like the rows on the
    // send options screen.
    private func legalRow(_ title: String, _ document: LegalDocumentService.Document) -> some View {
        Button {
            showLegal = document
        } label: {
            HStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 17))
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.leading, 50)
        }
        .padding(.horizontal, 16)
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
