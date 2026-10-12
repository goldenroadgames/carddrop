import SwiftUI
import Supabase

/// Shown instead of the whole app when the account or device is suspended.
/// A suspended user can still delete their account (App Store 5.1.1(v) and
/// privacy law still apply), appeal the suspension with the form below, and
/// read Help, the Terms and the Privacy Policy.
struct SuspendedView: View {
    @State private var showLegal: LegalDocumentService.Document?
    @State private var showAppealForm = false
    @State private var appeal: AppealService.Appeal?
    @State private var appealLoaded = false
    // False once the account has used up its reinstatements: this suspension is final.
    @State private var canAppeal = true

    private var hasOpenAppeal: Bool {
        guard let appeal else { return false }
        return appeal.resolved_at == nil
    }

    private var legalTitle: (LegalDocumentService.Document) -> String {
        { document in
            switch document {
            case .termsOfService: return "Terms of Service"
            case .privacyPolicy:  return "Privacy Policy"
            case .help:           return "Help"
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("Account Suspended")
                .font(.title2.weight(.semibold))
            Text("Your account has been suspended for violating our content standards or complaints about cards you sent.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            appealSection

            DeleteAccountButton()
                .font(.body)
                .padding(.top, 8)
            Spacer()
            HStack(spacing: 4) {
                Button("Help") { showLegal = .help }
                Text("·")
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
        .task { await refreshAppeal() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await refreshAppeal() }
        }
        .sheet(item: $showLegal) { document in
            NavigationStack {
                LegalDocumentView(title: legalTitle(document), document: document)
                .toolbar {
                    toolbarPillItem("Done", placement: .confirmationAction, style: .bare) { showLegal = nil }
                }
            }
        }
        .sheet(isPresented: $showAppealForm) {
            AppealFormView {
                showAppealForm = false
                Task { await refreshAppeal() }
            }
        }
    }

    // MARK: - Appeal

    @ViewBuilder
    private var appealSection: some View {
        if hasOpenAppeal {
            VStack(spacing: 4) {
                Text("Appeal received")
                    .font(.body.weight(.semibold))
                Text("We'll review it and update this screen.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)
        } else if appealLoaded && !canAppeal {
            Text("This suspension is final.")
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
        } else if appealLoaded {
            if let appeal, appeal.outcome == "denied" {
                VStack(spacing: 4) {
                    Text("Your appeal was reviewed and the suspension stays in place.")
                        .font(.body)
                        .foregroundColor(.secondary)
                    if let note = appeal.resolution, !note.isEmpty {
                        Text(note)
                            .font(.body)
                    }
                }
                .multilineTextAlignment(.center)
            } else {
                Text("If you think this was a mistake, you can appeal.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            Button("Appeal This Decision") { showAppealForm = true }
                .font(.body.weight(.semibold))
        }
    }

    private func refreshAppeal() async {
        appeal = await AppealService.latest()
        canAppeal = await AppealService.canAppeal()
        appealLoaded = true
    }
}

// MARK: - Appeal form

private struct AppealFormView: View {
    var onDone: () -> Void

    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private let maxLength = 1000

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tell us what happened and why you think the suspension was a mistake.")
                    .font(.body)
                    .foregroundColor(.secondary)
                TextEditor(text: $message)
                    .frame(minHeight: 160)
                    .padding(8)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator)))
                    .onChange(of: message) { _, newValue in
                        if newValue.count > maxLength { message = String(newValue.prefix(maxLength)) }
                    }
                HStack {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    Spacer()
                    Text("\(message.count)/\(maxLength)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button(action: send) {
                    Group {
                        if isSending {
                            ProgressView().tint(.white)
                        } else {
                            Text("Send Appeal")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.brandBlue)
                    .foregroundColor(.white)
                    .cornerRadius(999)
                }
                .disabled(isSending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                Spacer()
            }
            .padding()
            .navigationTitle("Appeal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem("Cancel", placement: .cancellationAction, style: .bare) { onDone() }
            }
        }
    }

    private func send() {
        Task {
            isSending = true
            errorMessage = nil
            let result = await AppealService.submit(message: message)
            isSending = false
            switch result {
            case .sent, .alreadyOpen:
                onDone()
            case .cooldown:
                errorMessage = "You can appeal again 30 days after a decision."
            case .notAllowed:
                errorMessage = "Appeals aren't available for this suspension."
            case .failed:
                errorMessage = "Couldn't send your appeal. Please try again."
            }
        }
    }
}

// MARK: - Service

/// Talks to the submit-appeal Edge Function (the only way to write an appeal:
/// clients can't write ban_reviews) and reads the user's own appeal row.
enum AppealService {
    struct Appeal: Decodable {
        let message: String?
        let created_at: Date?
        let resolved_at: Date?
        let outcome: String?       // "reinstated" | "denied" once decided
        let resolution: String?    // the note shown to the user
    }

    enum SubmitResult { case sent, alreadyOpen, cooldown, notAllowed, failed }

    /// The user's most recent appeal, if any.
    static func latest() async -> Appeal? {
        guard let userID = try? await supabase.auth.session.user.id else { return nil }
        let rows: [Appeal]? = try? await supabase
            .from("ban_reviews")
            .select("message, created_at, resolved_at, outcome, resolution")
            .eq("user_id", value: userID.uuidString)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows?.first
    }

    private struct SubmitBody: Encodable {
        let message: String?
        let deviceUUID: String
        let check: Bool?
    }

    private struct SubmitResponse: Decodable {
        let status: String?
        let error: String?
        let canAppeal: Bool?
    }

    /// Whether an appeal can still be made for this suspension. False once the
    /// account has been reinstated the allowed number of times (a final
    /// suspension). If the check fails, the form stays available; the server
    /// refuses a disallowed appeal anyway.
    static func canAppeal() async -> Bool {
        let body = SubmitBody(message: nil, deviceUUID: UserService.deviceUUID.uuidString, check: true)
        let response: SubmitResponse? = try? await supabase.functions
            .invoke("submit-appeal", options: FunctionInvokeOptions(body: body))
        return response?.canAppeal ?? true
    }

    static func submit(message: String) async -> SubmitResult {
        let body = SubmitBody(
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceUUID: UserService.deviceUUID.uuidString,
            check: nil
        )
        do {
            let response: SubmitResponse = try await supabase.functions
                .invoke("submit-appeal", options: FunctionInvokeOptions(body: body))
            return response.status == "already_open" ? .alreadyOpen : .sent
        } catch let fnError as FunctionsError {
            if case .httpError(_, let data) = fnError,
               let response = try? JSONDecoder().decode(SubmitResponse.self, from: data),
               let error = response.error {
                if error == "cooldown" { return .cooldown }
                if error == "no_appeals" { return .notAllowed }
            }
            return .failed
        } catch {
            return .failed
        }
    }
}
