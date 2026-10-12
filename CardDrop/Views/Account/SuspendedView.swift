import SwiftUI
import Supabase

/// Shown instead of the whole app when the account or device is suspended.
/// A suspended user can still delete their account (App Store 5.1.1(v) and
/// privacy law still apply), appeal the suspension with the form below, and
/// read Help, the Terms and the Privacy Policy. A FINAL suspension (no appeal
/// left, or a permanently banned device) gets the minimal "Account Disabled"
/// screen: one line, the legal links, and Delete Account only for a real login.
struct SuspendedView: View {
    /// True for a permanently disabled phone (known without a login): straight
    /// to the minimal "Account Disabled" screen, no server calls for appeals.
    var forceFinal = false

    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var monitor = SuspensionMonitor.shared
    @State private var showLegal: LegalDocumentService.Document?
    @State private var showAppealForm = false
    @State private var appeal: AppealService.Appeal?
    @State private var appealLoaded = false
    // False once the account has used up its reinstatements: this suspension is final.
    @State private var canAppeal = true
    // "about six months" / "about a month": how long until the account data is
    // deleted, read from the same settings the server uses.
    @State private var deletionPhrase: String?

    // Until the server answers, the remembered answer decides, so a final account
    // never flashes the ordinary Suspended page.
    private var isFinal: Bool { forceFinal || (appealLoaded ? !canAppeal : monitor.knownFinal) }

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
            if isFinal {
                Text("Account Disabled")
                    .font(.title2.weight(.semibold))
                Text("This account has been disabled.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                // An empty anonymous account has nothing to delete; a real login
                // (email or Apple) keeps the option (App Store 5.1.1(v)).
                if !authManager.isAnonymous {
                    DeleteAccountButton()
                        .font(.body)
                        .padding(.top, 8)
                }
            } else {
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
            }
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
        // Hidden behind a spinner until the appeal status is known, so the
        // screen doesn't jump when the Appeal section appears.
        .opacity(appealLoaded || forceFinal || monitor.knownFinal ? 1 : 0)
        .overlay { if !(appealLoaded || forceFinal || monitor.knownFinal) { ProgressView() } }
        .animation(.easeIn(duration: 0.2), value: appealLoaded)
        .task { await refreshAppeal() }
        .task {
            // Fallback: never leave the screen blank if the server is slow.
            try? await Task.sleep(for: .seconds(6))
            appealLoaded = true
        }
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

    // Everything under the first paragraph is ONE paragraph (same font and color):
    // the appeal status, then "If you don't appeal..." when an appeal is still
    // possible. The Appeal button sits below it as a separate control.
    private var appealParagraph: String {
        var parts: [String] = []
        if hasOpenAppeal {
            parts.append("Appeal received. We'll review it and update this screen.")
        } else {
            if let appeal, appeal.outcome == "denied" {
                // An appeal the sweeper closed unreviewed says so (and never claims
                // it was reviewed). The admin's note is internal: the app can't
                // even read that column.
                if appeal.auto_closed == true {
                    parts.append("Your appeal wasn't reviewed in time and has been closed, and your account is still suspended.")
                } else {
                    parts.append("Your appeal was denied and your account is still suspended.")
                }
                // A denied user can appeal again 30 days after the decision (the
                // server enforces it); until then no button.
                if let retryDate = appealRetryDate {
                    parts.append("You can appeal again after \(retryDate.formatted(date: .abbreviated, time: .omitted)).")
                }
            } else {
                parts.append("If you think this was a mistake, you can appeal.")
            }
            if let deletionPhrase {
                parts.append("If you don't appeal, your account data will be deleted after \(deletionPhrase).")
            }
        }
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private var appealSection: some View {
        if appealLoaded {
            Text(appealParagraph)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            if !hasOpenAppeal && appealRetryDate == nil {
                Button("Appeal This Decision") { showAppealForm = true }
                    .font(.body.weight(.semibold))
            }
        }
    }

    /// When a denied appeal can be repeated (30 days after the decision), or nil
    /// if the latest appeal wasn't denied or the wait is over.
    private var appealRetryDate: Date? {
        guard let appeal, appeal.outcome == "denied", let resolved = appeal.resolved_at,
              let retry = Calendar.current.date(byAdding: .day, value: 30, to: resolved),
              retry > Date() else { return nil }
        return retry
    }

    private func refreshAppeal() async {
        if forceFinal { appealLoaded = true; return }
        // The three questions are asked at the same time, not one after another.
        async let latest = AppealService.latest()
        async let eligible = AppealService.canAppeal()
        async let phrase = AppealService.deletionPhrase(final: false)
        appeal = await latest
        deletionPhrase = await phrase
        // nil = couldn't ask (offline): keep what we knew rather than guess.
        if let eligible = await eligible {
            canAppeal = eligible
            monitor.setKnownFinal(!eligible)
        } else if monitor.knownFinal {
            canAppeal = false
        }
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
        let auto_closed: Bool?     // closed by the sweeper without a review
    }

    enum SubmitResult { case sent, alreadyOpen, cooldown, notAllowed, failed }

    /// The user's most recent appeal, if any.
    static func latest() async -> Appeal? {
        guard let userID = try? await supabase.auth.session.user.id else { return nil }
        let rows: [Appeal]? = try? await supabase
            .from("ban_reviews")
            .select("message, created_at, resolved_at, outcome, auto_closed")
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

    private struct ConfigRow: Decodable { let value: String }

    /// "about 180 days": how long until a suspended account's data is deleted,
    /// from zz_config (suspension_delete_days for an unappealed suspension,
    /// final_suspension_delete_days for a final one). Falls back to the
    /// defaults (180 / 30) if the lookup fails.
    static func deletionPhrase(final: Bool) async -> String {
        let key = final ? "final_suspension_delete_days" : "suspension_delete_days"
        let row = try? await supabase
            .from("zz_config")
            .select("value")
            .eq("key", value: key)
            .single()
            .execute()
            .value as ConfigRow
        let days = row.flatMap { Int($0.value) }.flatMap { $0 > 0 ? $0 : nil } ?? (final ? 30 : 180)
        return "about \(days) days"
    }

    /// Whether an appeal can still be made for this suspension. False once the
    /// account has been reinstated the allowed number of times (a final
    /// suspension). nil if the check couldn't complete (the server refuses a
    /// disallowed appeal anyway).
    static func canAppeal() async -> Bool? {
        let body = SubmitBody(message: nil, deviceUUID: UserService.deviceUUID.uuidString, check: true)
        let response: SubmitResponse? = try? await supabase.functions
            .invoke("submit-appeal", options: FunctionInvokeOptions(body: body))
        return response?.canAppeal
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
