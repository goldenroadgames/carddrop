import SwiftUI
import CoreImage.CIFilterBuiltins
import MessageUI
import Supabase

// MARK: - Send Options sheet

// Compile-time check (not runtime) — this branch doesn't exist at all in
// device/App Store builds. The Simulator can't present MFMailComposeViewController
// or MFMessageComposeViewController (canSendMail()/canSendText() are always
// false), so without this, a digital send in the Simulator uploads
// successfully but the draft never flips to .sent, since that only happens
// in the composer's onSent callback.
private var isRunningInSimulator: Bool {
    #if targetEnvironment(simulator)
    true
    #else
    false
    #endif
}

struct SendOptionsView: View {
    @ObservedObject var draft: PostcardDraft
    let filteredImage: UIImage?
    let originalStatus: CardStatus
    let hasDraftSaved: Bool
    var onSaveUnsent: () -> Void
    var onSaveSent: () -> Void
    var onGoToFront: () -> Void
    var onGoToBack: () -> Void
    var onGoToAddress: () -> Void
    var onFinish: () -> Void
    var onSendToSomeoneElse: () -> Void
    var onEditCard: () -> Void

    @EnvironmentObject private var authManager: AuthManager

    @State private var showMailComposer = false
    @State private var showMessageComposer = false
    @State private var isSending = false
    @State private var teaserImage: UIImage? = nil
    @State private var cardSendResult: CardSendResult? = nil
    @State private var sendError: String? = nil
    @State private var showSendErrorAlert = false
    @State private var hasSent = false
    @State private var showMissingPhotoAlert = false
    @State private var showStorageUpgrade = false
    @State private var showCreateAccount = false
    @State private var showVerifyEmail = false
    @State private var limitPrompt: LimitPrompt? = nil
    @State private var showEmailRecipients = false
    @State private var pendingEmailRecipients: [RecipientContact] = []
    @State private var showMessageRecipients = false
    @State private var pendingMessageRecipients: [RecipientContact] = []

    private struct LimitPrompt: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let isAnonymous: Bool
    }
    @EnvironmentObject private var draftManager: DraftManager
    @EnvironmentObject private var addressBook: AddressBookManager

    // Inline flip preview — front -> 4x6 back -> 6x9 back -> loop, cycling
    // forward on every tap. Replaces the old CardFlipPreviewSheet modal;
    // the thumbnail itself now carries the flip capability directly.
    private enum CardFace: Int, CaseIterable {
        case front, back4x6, back6x9
    }

    @State private var face: CardFace = .front
    @State private var previewScaleX: CGFloat = 1.0
    @State private var backRenderImage: UIImage? = nil
    @State private var back6x9RenderImage: UIImage? = nil

    private var currentPreviewImage: UIImage? {
        switch face {
        case .front:   return teaserImage ?? filteredImage
        case .back4x6: return backRenderImage
        case .back6x9: return back6x9RenderImage
        }
    }

    private var currentPreviewSizeLabel: String? {
        switch face {
        case .front:   return nil
        case .back4x6: return "\n4x6 Standard Size"
        case .back6x9: return "6x9 Deluxe Size - more than twice the size of a standard size card - bigger picture, larger text"
        }
    }

    private func flipPreview() {
        withAnimation(.easeIn(duration: 0.18)) { previewScaleX = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            let allFaces = CardFace.allCases
            let nextIndex = (allFaces.firstIndex(of: face)! + 1) % allFaces.count
            face = allFaces[nextIndex]
            withAnimation(.easeOut(duration: 0.18)) { previewScaleX = 1 }
        }
    }

    var body: some View {
        VStack(spacing: 0) {

        // A still-editable (unsent) session jumps straight back to Style It /
        // Write Card in place. A sent card's whole flow is read-only (see
        // chevronControls in CreateFlowView), so editing one instead clones
        // it and opens the clone at Style It — same as "Copy & Edit" on the
        // sent-card detail sheet.
        Group {
            if originalStatus == .sent {
                Button(action: onEditCard) {
                    Text("Copy & Edit")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.brandBlue)
                        .foregroundColor(.white)
                        .cornerRadius(999)
                }
            } else {
                HStack(spacing: 12) {
                    Button(action: onGoToFront) {
                        Text("Edit Front")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.brandBlue)
                            .foregroundColor(.white)
                            .cornerRadius(999)
                    }
                    Button(action: onGoToBack) {
                        Text("Edit Back")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.brandBlue)
                            .foregroundColor(.white)
                            .cornerRadius(999)
                    }
                }
            }
        }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))

        GeometryReader { geo in
        // Content block — label (if any), image, "Tap to flip" — packed
        // tightly with 12pt between each piece using nothing but a plain
        // VStack (no Spacers, no per-child maxHeight/alignment tricks that
        // could push them apart). The block sizes itself to its own content,
        // then that whole compact block is centered as a unit — both axes —
        // via the single .frame(maxWidth: .infinity, maxHeight: .infinity)
        // on the VStack itself below. The image is capped only by width;
        // scaledToFit derives its height from that, so it never expands to
        // fill the safe zone and shove its siblings apart.
        let maxImageWidth = geo.size.width - 32

        VStack(spacing: 0) {
            if let label = currentPreviewSizeLabel {
                Text(label)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.brandBlue)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: maxImageWidth - 20, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }

            if let img = currentPreviewImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: maxImageWidth)
                    .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
                    .scaleEffect(x: previewScaleX, y: 1)
                    .onTapGesture { flipPreview() }
            } else {
                ProgressView()
                    .frame(width: maxImageWidth, height: 150)
            }

            Text("Tap to flip")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gray)
                .padding(.top, 8)
        }
            .padding(.top, 10)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .overlay {
                if isSending {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Sending…")
                                .font(.subheadline)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .alert("Send Failed", isPresented: $showSendErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sendError ?? "Something went wrong. Please try again.")
            }
        .onAppear {
            teaserImage       = draftManager.loadFront(for: draft.cardID)
            backRenderImage   = draftManager.loadBack(for: draft.cardID)
            back6x9RenderImage = draftManager.loadBack6x9(for: draft.cardID)
        }
        .onChange(of: filteredImage) { _, newImage in
            guard newImage != nil else { return }
            guard originalStatus == .sent else { return }
            // Card already uploaded — pre-populate the URL so re-sends skip the upload
            let urlString = "https://carddropapp.com/card/\(draft.cardID.uuidString)"
            if let url = URL(string: urlString) {
                cardSendResult = CardSendResult(cardID: draft.cardID, cardURL: url, sendsRemainingMonthly: -1, sendsRemainingLifetime: -1, tier: "unknown")
            }
            hasSent = true
        }
        .sheet(isPresented: $showMailComposer) {
            if let result = cardSendResult {
                MailComposeView(
                    compositeImageURL: result.compositeImageURL,
                    cardURL: result.cardURL,
                    recipientEmails: pendingEmailRecipients.map(\.value),
                    cardID: result.cardID,
                    senderNickname: draft.senderNickname.isEmpty ? nil : draft.senderNickname,
                    onSent: {
                        Task {
                            await insertEmailRecipients(entries: pendingEmailRecipients, cardID: result.cardID)
                            onSaveSent()
                            onFinish()
                        }
                    },
                    onFailed: {
                        sendError = "Mail failed to send. Please try again."
                        showSendErrorAlert = true
                    }
                )
            }
        }
        .sheet(isPresented: $showEmailRecipients) {
            EmailRecipientsSheet(initialEmail: draft.recipientEmail) { entries in
                performEmailSend(entries: entries)
            }
        }
        .sheet(isPresented: $showMessageComposer) {
            if let result = cardSendResult {
                MessageComposeView(
                    teaserImage: teaserImage,
                    cardURL: result.cardURL,
                    recipients: pendingMessageRecipients.map(\.value),
                    cardID: result.cardID,
                    senderNickname: draft.senderNickname.isEmpty ? nil : draft.senderNickname,
                    onSent: {
                        Task {
                            await insertMessageRecipients(entries: pendingMessageRecipients, cardID: result.cardID)
                            onSaveSent()
                            onFinish()
                        }
                    },
                    onFailed: {
                        sendError = "Message failed to send. Please try again."
                        showSendErrorAlert = true
                    }
                )
            }
        }
        .sheet(isPresented: $showMessageRecipients) {
            MessageRecipientsSheet(initialRecipient: draft.recipientPhone.isEmpty ? draft.recipientEmail : draft.recipientPhone) { entries in
                performTextSend(entries: entries)
            }
        }
        .sheet(isPresented: $showStorageUpgrade) {
            StorageUpgradeView {
                authManager.setTierUnlimited()
            }
        }
        } // end GeometryReader
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                // Print and Mail — anchored directly above "Send Digitally"
                // rather than scrolling with the rest of the List; padded
                // below so it doesn't graze "Send Digitally" underneath it.
                Text("Print and Mail")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.brandBlue)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 16)

                Group {
                    if authManager.isAnonymous {
                        sendRow(
                            icon: "photo",
                            title: "Mail Real Postcard",
                            subtitle: "Create Account to Mail Real Postcards",
                            color: .brandBlue
                        ) { showCreateAccount = true }
                    } else {
                        // Account exists, so "Create Account" no longer applies —
                        // Mail Real Postcard becomes reachable in principle, but
                        // isn't wired to anything yet.
                        comingSoonRow(icon: "photo", title: "Mail Real Postcard",
                                      subtitle: "Printed & mailed for you")
                    }
                }
                .padding(.horizontal, 16)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

                // Send Digitally — anchored directly above Finish rather than
                // scrolling with the rest of the List.
                Text("Send Digitally — Free")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.brandBlue)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 16)

                VStack(spacing: 0) {
                    sendRow(
                        icon: "envelope",
                        title: "Email",
                        subtitle: "Send as an interactive postcard",
                        color: .blue
                    ) { sendEmail() }
                    .padding(.horizontal, 16)

                    Divider().padding(.leading, 66)

                    sendRow(
                        icon: "message",
                        title: "Text Message",
                        subtitle: "Send via Messages",
                        color: .green
                    ) { sendText() }
                    .padding(.horizontal, 16)
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal, 16)

                if !authManager.hasPermanentStorage && !authManager.isAnonymous && authManager.isEmailVerified {
                    sendRow(
                        icon: "archivebox",
                        title: "Cards expire after 30 days",
                        subtitle: "Upgrade once for permanent storage — $9.99",
                        color: .purple
                    ) { showStorageUpgrade = true }
                    .padding(.horizontal, 16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .padding(.horizontal, 16)
                }

                // Finish button
                Button(action: handleFinish) {
                    Text("Finish")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.brandBlue)
                        .foregroundColor(.white)
                        .cornerRadius(999)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .padding(.top, 8)
            .background(Color(uiColor: .systemGroupedBackground))
        }

        } // VStack
        .alert("No Photo", isPresented: $showMissingPhotoAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add a photo before sending.")
        }
        .alert(item: $limitPrompt) { prompt in
            Alert(
                title: Text(""),
                message: Text(prompt.title + "\n" + prompt.message),
                primaryButton: .default(Text("Yes")) {
                    if prompt.isAnonymous { showCreateAccount = true }
                    else { showVerifyEmail = true }
                },
                secondaryButton: .cancel(Text("No")) {
                    handleFinish()
                }
            )
        }
        .sheet(isPresented: $showCreateAccount) {
            SubscribeGateView(onSuccess: { showCreateAccount = false })
                .environmentObject(authManager)
                .environmentObject(draftManager)
                .environmentObject(addressBook)
        }
        .sheet(isPresented: $showVerifyEmail) {
            OTPVerificationView(onSuccess: { showVerifyEmail = false }, onCancel: { handleFinish() })
                .environmentObject(authManager)
                .environmentObject(draftManager)
                .environmentObject(addressBook)
        }
    }

    private func handleFinish() {
        if !hasSent {
            onSaveUnsent()
            NotificationCenter.default.post(name: .navigateToDrafts, object: nil)
        }
        onFinish()
    }

    // Only requirement for a digital send is a photo.
    // Blank message gets a marketing plug server-side; recipient is filled in the native composer.
    private func guardSend(action: @escaping () -> Void) {
        guard draft.image != nil || hasSent else { showMissingPhotoAlert = true; return }
        action()
    }

    // MARK: - Row builder

    @ViewBuilder
    private func sendRow(icon: String, title: String, subtitle: String? = nil, color: Color,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .lineLimit(1)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func comingSoonRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.secondary.opacity(0.4))
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                    .foregroundColor(.primary.opacity(0.4))
                Text(subtitle)
                    .lineLimit(1)
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.4))
            }
            Spacer()
            Text("Coming soon")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Render + share

    private func setLimitPrompt(for error: CardUploadService.UploadError) {
        switch error {
        case .monthlyLimitReached:
            limitPrompt = LimitPrompt(
                title: "Monthly Limit Reached",
                message: authManager.isAnonymous
                    ? "You've used your free sends for this month. Create a free account to get more free sends."
                    : "You've used your 5 free sends this month. Verify your email to unlock unlimited sends - it's free.",
                isAnonymous: authManager.isAnonymous
            )
        case .lifetimeLimitReached:
            limitPrompt = LimitPrompt(
                title: "Send Limit Reached",
                message: "You've used all of your free sends. Create a free account to keep sending.",
                isAnonymous: true
            )
        default: break
        }
    }

    private func sendEmail() {
        guard !isSending else { return }
        guard draft.image != nil else { showMissingPhotoAlert = true; return }
        Task { @MainActor in
            do {
                try await CardUploadService.checkSendLimits()
                showEmailRecipients = true
            } catch let error as CardUploadService.UploadError {
                setLimitPrompt(for: error)
            } catch {}
        }
    }

    /// Splits a full name (e.g. from a contact lookup) into first/last, matching the
    /// convention used for the To/From step's recipient fields.
    private func splitName(_ name: String) -> (first: String, last: String) {
        let parts = name.components(separatedBy: " ").filter { !$0.isEmpty }
        return (parts.first ?? "", parts.dropFirst().joined(separator: " "))
    }

    private func performEmailSend(entries: [RecipientContact]) {
        Task { @MainActor in
            await uploadAndSend {
                pendingEmailRecipients = entries
                if MFMailComposeViewController.canSendMail() {
                    showMailComposer = true
                } else if isRunningInSimulator, let result = cardSendResult {
                    // Simulator can't present the Mail composer at all, so the
                    // real device completion path (MailComposeView's onSent)
                    // never fires and the card would silently never flip to
                    // .sent. The upload above already succeeded for real —
                    // finish the same way onSent would, just skipping the
                    // composer UI itself.
                    Task {
                        await insertEmailRecipients(entries: pendingEmailRecipients, cardID: result.cardID)
                        onSaveSent()
                        onFinish()
                    }
                }
            }
        }
    }

    private func insertEmailRecipients(entries: [RecipientContact], cardID: UUID) async {
        struct Row: Encodable {
            let card_id: String
            let email: String
            let first_name: String?
            let last_name: String?
            let nickname: String?
            let send_method: String
        }
        let nickname = draft.recipientNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        for entry in entries {
            let (first, last) = splitName(entry.name)
            let row = Row(
                card_id: cardID.uuidString,
                email: entry.value,
                first_name: first.isEmpty ? nil : first,
                last_name: last.isEmpty ? nil : last,
                nickname: nickname.isEmpty ? nil : nickname,
                send_method: "email"
            )
            try? await supabase
                .from("card_recipients")
                .insert(row)
                .execute()
            addressBook.saveIfNew(
                name: entry.name,
                nickname: nickname,
                address: "",
                email: entry.value,
                phone: "",
                role: .recipient,
                nameIsAuthoritative: entry.isFromContactPicker
            )
        }
    }

    private func sendText() {
        guard !isSending else { return }
        guard draft.image != nil else { showMissingPhotoAlert = true; return }
        Task { @MainActor in
            do {
                try await CardUploadService.checkSendLimits()
                showMessageRecipients = true
            } catch let error as CardUploadService.UploadError {
                setLimitPrompt(for: error)
            } catch {}
        }
    }

    private func performTextSend(entries: [RecipientContact]) {
        Task { @MainActor in
            await uploadAndSend {
                pendingMessageRecipients = entries
                if MFMessageComposeViewController.canSendText() {
                    showMessageComposer = true
                } else if isRunningInSimulator, let result = cardSendResult {
                    // See matching comment in performEmailSend — Simulator
                    // can't present the Messages composer, so mimic
                    // MessageComposeView's onSent completion directly.
                    Task {
                        await insertMessageRecipients(entries: pendingMessageRecipients, cardID: result.cardID)
                        onSaveSent()
                        onFinish()
                    }
                }
            }
        }
    }

    private func insertMessageRecipients(entries: [RecipientContact], cardID: UUID) async {
        struct Row: Encodable {
            let card_id: String
            let email: String?
            let phone: String?
            let first_name: String?
            let last_name: String?
            let nickname: String?
            let send_method: String
        }
        let nickname = draft.recipientNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        for entry in entries {
            let isEmail = entry.value.contains("@")
            let (first, last) = splitName(entry.name)
            let row = Row(
                card_id: cardID.uuidString,
                email: isEmail ? entry.value : nil,
                phone: isEmail ? nil : entry.value,
                first_name: first.isEmpty ? nil : first,
                last_name: last.isEmpty ? nil : last,
                nickname: nickname.isEmpty ? nil : nickname,
                send_method: "text"
            )
            try? await supabase
                .from("card_recipients")
                .insert(row)
                .execute()
            addressBook.saveIfNew(
                name: entry.name,
                nickname: nickname,
                address: "",
                email: isEmail ? entry.value : "",
                phone: isEmail ? "" : entry.value,
                role: .recipient,
                nameIsAuthoritative: entry.isFromContactPicker
            )
        }
    }

    private func uploadAndSend(then show: @escaping () -> Void) async {
        // Sent card re-opened: files already in Supabase, skip upload and go straight to composer
        if cardSendResult != nil {
            teaserImage = draftManager.loadFront(for: draft.cardID)
            show()
            return
        }

        guard let frontData = draftManager.loadFrontData(for: draft.cardID),
              let backData  = draftManager.loadBackData(for: draft.cardID) else { return }
        let back6x9Data = draftManager.loadBack6x9Data(for: draft.cardID)

        teaserImage = draftManager.loadFront(for: draft.cardID)

        // Plain card front, uploaded here so email can reference it by URL
        // — an embedded cid: attachment doesn't render reliably across mail
        // clients (confirmed broken in Gmail).
        let compositeData: Data? = frontData

        // Upload + call Edge Function
        isSending = true
        do {
            let frontInk = draft.qrOverlays.first(where: { !$0.userInputText.isEmpty })?.content
            let backInk: String? = (draft.includeBackMessageQR && !draft.backMessageQRContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ? draft.backMessageQRContent : nil
            let result = try await CardUploadService.send(
                cardID: draft.cardID,
                frontData: frontData,
                backData: backData,
                back6x9Data: back6x9Data,
                compositeData: compositeData,
                frontIsPortrait: draft.orientation == .portrait,
                frontInkMessage: frontInk,
                backInkMessage: backInk,
                senderNickname: draft.senderNickname.isEmpty ? nil : draft.senderNickname,
                recipientNickname: draft.recipientNickname.isEmpty ? nil : draft.recipientNickname,
                recipientName: draft.recipientName.isEmpty ? nil : draft.recipientName,
                recipientPhone: draft.recipientPhone.isEmpty ? nil : draft.recipientPhone,
                recipientEmail: draft.recipientEmail.isEmpty ? nil : draft.recipientEmail,
                messagePreview: String(draft.message.prefix(100))
            )
            cardSendResult = result
            hasSent = true
            show()
        } catch let error as CardUploadService.UploadError {
            switch error {
            case .monthlyLimitReached, .lifetimeLimitReached:
                setLimitPrompt(for: error)
            default:
                sendError = error.localizedDescription
                showSendErrorAlert = true
            }
        } catch {
            sendError = error.localizedDescription
            showSendErrorAlert = true
        }
        isSending = false
    }

}

// MARK: - Mail composer bridge

struct MailComposeView: UIViewControllerRepresentable {
    var compositeImageURL: URL?
    var cardURL: URL
    var recipientEmails: [String]
    var cardID: UUID
    var senderNickname: String?
    var onSent: () -> Void
    var onFailed: () -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        if !recipientEmails.isEmpty { vc.setToRecipients(recipientEmails) }
        let from = senderNickname?.isEmpty == false ? senderNickname! : "You"
        vc.setSubject("\(from) sent a CardDrop")

        // Hosted image (uploaded alongside front/back at send time — see
        // CardUploadService.send's compositeData param), not an embedded
        // cid: attachment: cid: references don't render reliably across
        // mail clients (confirmed broken in Gmail), whereas a plain hosted
        // <img src> works everywhere, same as the front/back teaser images.
        let url = cardURL.absoluteString
        let imageTag = compositeImageURL.map {
            """
            <a href="\(url)" style="display:block;text-decoration:none;">
              <img src="\($0.absoluteString)" style="max-width:100%;border-radius:10px;display:block;margin:0 auto 20px;" />
            </a>
            """
        } ?? ""
        let html = """
        <html>
        <body style="font-family:-apple-system,Helvetica,sans-serif;max-width:600px;margin:0 auto;padding:20px;color:#222;text-align:center;">
        \(imageTag)
        <p style="font-size:15px;margin:0 0 12px;">Tap to open it</p>
        <p style="font-size:14px;margin:0;"><a href="\(url)" style="color:#0066FF;">\(url)</a></p>
        </body>
        </html>
        """
        vc.setMessageBody(html, isHTML: true)
        return vc
    }

    func updateUIViewController(_ uvc: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposeView
        init(_ parent: MailComposeView) { self.parent = parent }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.dismiss()
            switch result {
            case .sent:
                parent.onSent()
            case .failed:
                parent.onFailed()
            default:
                break
            }
        }
    }
}

// MARK: - Message composer bridge

struct MessageComposeView: UIViewControllerRepresentable {
    var teaserImage: UIImage?
    var cardURL: URL
    var recipients: [String]
    var cardID: UUID
    var senderNickname: String?
    var onSent: () -> Void
    var onFailed: () -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.messageComposeDelegate = context.coordinator
        if !recipients.isEmpty { vc.recipients = recipients }
        let from = senderNickname?.isEmpty == false ? senderNickname! : "You"
        vc.body = "\(from) sent a CardDrop\nTap to open it.\n\n\n\(cardURL.absoluteString)"
        if let img = teaserImage {
            let thumbnail = PostcardHTMLGenerator.scaledForThumbnail(img)
            if let data = thumbnail.jpegData(compressionQuality: 0.7) {
                vc.addAttachmentData(data, typeIdentifier: "public.jpeg", filename: "postcard.jpg")
            }
        }
        return vc
    }

    func updateUIViewController(_ uvc: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let parent: MessageComposeView
        init(_ parent: MessageComposeView) { self.parent = parent }
        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            parent.dismiss()
            switch result {
            case .sent:
                parent.onSent()
            case .failed:
                parent.onFailed()
            default:
                break
            }
        }
    }
}

// MARK: - UIActivityViewController bridge

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - Card Checklist

struct CardChecklistView: View {
    @ObservedObject var draft: PostcardDraft

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            checklistSection("Required") {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                    checklistRow("Photo", filled: draft.image != nil, style: .required)
                    checklistRow("Message", filled: !draft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, style: .required)
                }
            }
            checklistSection("For Mailing") {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                    checklistRow("To Address", filled: !draft.recipientStreet.isEmpty, style: .mailing)
                    checklistRow("From Address", filled: !draft.senderStreet.isEmpty, style: .mailing)
                }
            }
            checklistSection("Optional") {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                    checklistRow("To Email", filled: !draft.recipientEmail.isEmpty, style: .optional)
                    checklistRow("From Email", filled: !draft.senderEmail.isEmpty, style: .optional)
                    checklistRow("To Phone", filled: !draft.recipientPhone.isEmpty, style: .optional)
                    checklistRow("From Phone", filled: !draft.senderPhone.isEmpty, style: .optional)
                }
            }
        }
    }

    private enum RowStyle { case required, mailing, optional }

    @ViewBuilder
    private func checklistSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.top, 14)
                .padding(.bottom, 4)
            content()
        }
    }

    @ViewBuilder
    private func checklistRow(_ label: String, filled: Bool, style: RowStyle) -> some View {
        HStack(spacing: 6) {
            Image(systemName: filled ? "checkmark.circle.fill" : "circle")
                .foregroundColor(
                    filled ? .green :
                    style == .required ? .red :
                    style == .mailing ? Color.brandBlue :
                    .secondary
                )
                .font(.system(size: 15))
            Text(label)
                .font(.footnote)
                .foregroundColor(style == .optional ? .secondary : .primary)
        }
        .padding(.vertical, 2)
    }
}


// MARK: - Custom Text Border

struct CustomTextBorderView: View {
    let cardSize: CGSize
    let orientation: PostcardOrientation
    let text: String
    let fontName: String
    let textColor: Color

    private var borderThickness: CGFloat {
        switch orientation {
        case .landscape: return cardSize.height * (3.0 / 8.0 / 4.0)
        case .portrait:  return cardSize.width  * (3.0 / 8.0 / 4.0)
        }
    }

    // ~12pt at typical screen preview (card height ~280pt)
    private var fontSize: CGFloat { borderThickness * 0.43 }

    // Half the border thickness — keeps arc centered in the strip at corners
    private var cornerRadius: CGFloat { borderThickness / 2 }

    // Letter spacing: spreads characters apart so they don't crowd around the arc bends
    private var tracking: CGFloat { fontSize * 0.20 }

    var body: some View {
        Canvas { context, _ in
            guard !text.isEmpty else { return }
            let W = cardSize.width, H = cardSize.height
            let t = borderThickness, fs = fontSize, r = cornerRadius

            let sH = W - t - 2 * r          // straight length top / bottom
            let sV = H - t - 2 * r          // straight length left / right
            let arc = r * .pi / 2            // quarter-circle arc length
            guard sH > 0, sV > 0 else { return }
            let perimeter = 2 * (sH + sV) + 4 * arc

            let uiFont = UIFont(name: fontName, size: fs) ?? UIFont.systemFont(ofSize: fs)
            let attrs: [NSAttributedString.Key: Any] = [.font: uiFont]

            let chars = Array(text)
            let charWidths = chars.map { c in
                (String(c) as NSString).size(withAttributes: attrs).width
            }
            let tk = tracking
            // phraseWidth includes inter-character tracking
            let phraseWidth = charWidths.reduce(0, +) + tk * CGFloat(max(0, chars.count - 1))
            guard phraseWidth > 0 else { return }

            let reps = max(1, Int(perimeter / phraseWidth))
            let gap  = (perimeter - CGFloat(reps) * phraseWidth) / CGFloat(reps)

            for rep in 0..<reps {
                let repStart = CGFloat(rep) * (phraseWidth + gap)
                var charOffset: CGFloat = 0
                for (i, char) in chars.enumerated() {
                    let cw = charWidths[i]
                    let d  = repStart + charOffset + cw / 2.0
                    let (pos, angleDeg) = pathPoint(d: d, W: W, H: H, t: t, r: r,
                                                    sH: sH, sV: sV, arc: arc, perim: perimeter)
                    var ctx = context
                    ctx.transform = CGAffineTransform(translationX: pos.x, y: pos.y)
                        .rotated(by: angleDeg * .pi / 180.0)
                    ctx.draw(
                        Text(String(char))
                            .font(.custom(fontName, size: fs))
                            .foregroundColor(textColor),
                        at: .zero, anchor: .center
                    )
                    charOffset += cw + (i < chars.count - 1 ? tk : 0)
                }
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
    }

    /// Returns (centerPoint, directionDegrees) for distance `d` along the rounded border path.
    /// 8 segments clockwise: top straight → TR arc → right straight → BR arc →
    ///                        bottom straight → BL arc → left straight → TL arc → repeat
    private func pathPoint(d: CGFloat, W: CGFloat, H: CGFloat, t: CGFloat, r: CGFloat,
                           sH: CGFloat, sV: CGFloat, arc: CGFloat, perim: CGFloat) -> (CGPoint, CGFloat) {
        var dist = d.truncatingRemainder(dividingBy: perim)
        if dist < 0 { dist += perim }

        func arcPt(_ cx: CGFloat, _ cy: CGFloat, startDeg: CGFloat, α: CGFloat, baseDeg: CGFloat) -> (CGPoint, CGFloat) {
            let rad = (startDeg + 90 * α) * .pi / 180
            return (CGPoint(x: cx + r * cos(rad), y: cy + r * sin(rad)), baseDeg + 90 * α)
        }

        // Top straight: (t/2+r, t/2) → (W-t/2-r, t/2)
        if dist < sH { return (CGPoint(x: t/2 + r + dist, y: t/2), 0) }
        dist -= sH

        // Top-right arc: center (W-t/2-r, t/2+r), starts at 270°, direction starts at 0°
        if dist < arc { return arcPt(W-t/2-r, t/2+r, startDeg: 270, α: dist/arc, baseDeg: 0) }
        dist -= arc

        // Right straight: (W-t/2, t/2+r) → (W-t/2, H-t/2-r)
        if dist < sV { return (CGPoint(x: W-t/2, y: t/2 + r + dist), 90) }
        dist -= sV

        // Bottom-right arc: center (W-t/2-r, H-t/2-r), starts at 0°, direction starts at 90°
        if dist < arc { return arcPt(W-t/2-r, H-t/2-r, startDeg: 0, α: dist/arc, baseDeg: 90) }
        dist -= arc

        // Bottom straight: (W-t/2-r, H-t/2) → (t/2+r, H-t/2)
        if dist < sH { return (CGPoint(x: W-t/2-r - dist, y: H-t/2), 180) }
        dist -= sH

        // Bottom-left arc: center (t/2+r, H-t/2-r), starts at 90°, direction starts at 180°
        if dist < arc { return arcPt(t/2+r, H-t/2-r, startDeg: 90, α: dist/arc, baseDeg: 180) }
        dist -= arc

        // Left straight: (t/2, H-t/2-r) → (t/2, t/2+r)
        if dist < sV { return (CGPoint(x: t/2, y: H-t/2-r - dist), 270) }
        dist -= sV

        // Top-left arc: center (t/2+r, t/2+r), starts at 180°, direction starts at 270°
        let α = min(dist / arc, 1)
        return arcPt(t/2+r, t/2+r, startDeg: 180, α: α, baseDeg: 270)
    }
}

// MARK: - Email Recipients Sheet

private struct SlotIndex: Identifiable { let id: Int }

/// A digital-send recipient captured from either free-text entry or a contact lookup.
/// `name` is empty when the recipient was typed in rather than picked from Contacts.
/// `isFromContactPicker` is true only when `value` still matches what the picker set —
/// if the user edits the field afterward, it self-corrects to false since the two no
/// longer match, and `name` should then be treated as stale/unreliable.
struct RecipientContact {
    let name: String
    let value: String
    let isFromContactPicker: Bool
}

struct EmailRecipientsSheet: View {
    let initialEmail: String
    var onSend: ([RecipientContact]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var emails: [String]
    @State private var names: [String]
    @State private var contactPickedEmails: [Int: String] = [:]
    @State private var pickerSlot: SlotIndex? = nil

    private let slotCount = 6

    init(initialEmail: String, onSend: @escaping ([RecipientContact]) -> Void) {
        self.initialEmail = initialEmail
        self.onSend = onSend
        var arr = Array(repeating: "", count: 6)
        if !initialEmail.isEmpty { arr[0] = initialEmail }
        _emails = State(initialValue: arr)
        _names = State(initialValue: Array(repeating: "", count: 6))
    }

    private func isValidEmail(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return true }
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return t.range(of: pattern, options: .regularExpression) != nil
    }

    private var validEntries: [RecipientContact] {
        emails.indices.compactMap { index in
            let trimmedEmail = emails[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedEmail.isEmpty, isValidEmail(trimmedEmail) else { return nil }
            let isFromPicker = contactPickedEmails[index] == trimmedEmail
            return RecipientContact(
                name: names[index].trimmingCharacters(in: .whitespacesAndNewlines),
                value: trimmedEmail,
                isFromContactPicker: isFromPicker
            )
        }
    }

    private var hasInvalidEntry: Bool {
        emails.contains {
            let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && !isValidEmail(t)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(0..<slotCount, id: \.self) { i in
                        emailRow(index: i)
                    }
                } header: {
                    Text("To")
                        .font(.system(size: 13, weight: .regular))
                        .textCase(.none)
                } footer: {
                    if hasInvalidEntry {
                        Text("Fix invalid email addresses before sending.")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Send via Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem("Cancel", placement: .cancellationAction, style: .bare) { dismiss() }
                toolbarPillItem("Send", placement: .confirmationAction, emphasis: .primary, style: .bare, isDisabled: hasInvalidEntry) {
                    onSend(validEntries)
                    dismiss()
                }
            }
            .sheet(item: $pickerSlot) { slot in
                ContactPickerView { name, _, email, _ in
                    if !email.isEmpty {
                        emails[slot.id] = email
                        names[slot.id] = name
                        contactPickedEmails[slot.id] = email
                    }
                }
            }
        }
        .dynamicTypeSize(.medium ... .xxxLarge)
    }

    @ViewBuilder
    private func emailRow(index: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                pickerSlot = SlotIndex(id: index)
            } label: {
                Image(systemName: "person.crop.circle.badge.plus")
                    .foregroundColor(.accentColor)
                    .frame(minWidth: 36, minHeight: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            let trimmed = emails[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let isInvalid = !trimmed.isEmpty && !isValidEmail(trimmed)

            TextField(index == 0 ? "Recipient email" : "Add another email",
                      text: $emails[index])
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .foregroundColor(isInvalid ? .red : .primary)
        }
    }
}

// MARK: - Message Recipients Sheet

struct MessageRecipientsSheet: View {
    let initialRecipient: String
    var onSend: ([RecipientContact]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recipients: [String]
    @State private var names: [String]
    @State private var contactPickedValues: [Int: String] = [:]
    @State private var pickerSlot: SlotIndex? = nil

    private let slotCount = 6

    init(initialRecipient: String, onSend: @escaping ([RecipientContact]) -> Void) {
        self.initialRecipient = initialRecipient
        self.onSend = onSend
        var arr = Array(repeating: "", count: 6)
        if !initialRecipient.isEmpty { arr[0] = initialRecipient }
        _recipients = State(initialValue: arr)
        _names = State(initialValue: Array(repeating: "", count: 6))
    }

    private func isValidEmail(_ s: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    private func isValidPhone(_ s: String) -> Bool {
        let digits = s.filter { $0.isNumber }
        guard digits.count >= 7 else { return false }
        let pattern = #"^\+?[\d\s\-().]{7,}$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    private func isValid(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return true }
        return t.contains("@") ? isValidEmail(t) : isValidPhone(t)
    }

    private var validEntries: [RecipientContact] {
        recipients.indices.compactMap { index in
            let trimmed = recipients[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, isValid(trimmed) else { return nil }
            let isFromPicker = contactPickedValues[index] == trimmed
            return RecipientContact(
                name: names[index].trimmingCharacters(in: .whitespacesAndNewlines),
                value: trimmed,
                isFromContactPicker: isFromPicker
            )
        }
    }

    private var hasInvalidEntry: Bool {
        recipients.contains {
            let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && !isValid(t)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(0..<slotCount, id: \.self) { i in
                        recipientRow(index: i)
                    }
                } header: {
                    Text("To")
                        .font(.system(size: 13, weight: .regular))
                        .textCase(.none)
                } footer: {
                    if hasInvalidEntry {
                        Text("Fix invalid entries before sending.")
                            .foregroundColor(.red)
                    } else {
                        Text("Enter phone numbers or email addresses.")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Send via Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem("Cancel", placement: .cancellationAction, style: .bare) { dismiss() }
                toolbarPillItem("Send", placement: .confirmationAction, emphasis: .primary, style: .bare, isDisabled: hasInvalidEntry) {
                    onSend(validEntries)
                    dismiss()
                }
            }
            .sheet(item: $pickerSlot) { slot in
                ContactPickerView { name, _, email, phone in
                    let value = phone.isEmpty ? email : phone
                    if !value.isEmpty {
                        recipients[slot.id] = value
                        names[slot.id] = name
                        contactPickedValues[slot.id] = value
                    }
                }
            }
        }
        .dynamicTypeSize(.medium ... .xxxLarge)
    }

    @ViewBuilder
    private func recipientRow(index: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                pickerSlot = SlotIndex(id: index)
            } label: {
                Image(systemName: "person.crop.circle.badge.plus")
                    .foregroundColor(.accentColor)
                    .frame(minWidth: 36, minHeight: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            let trimmed = recipients[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let isInvalid = !trimmed.isEmpty && !isValid(trimmed)

            TextField(index == 0 ? "Phone or email" : "Add another",
                      text: $recipients[index])
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .foregroundColor(isInvalid ? .red : .primary)
        }
    }
}

#Preview {
    SendOptionsView(
        draft: PostcardDraft(), filteredImage: nil, originalStatus: .unsent, hasDraftSaved: false,
        onSaveUnsent: {}, onSaveSent: {}, onGoToFront: {}, onGoToBack: {}, onGoToAddress: {}, onFinish: {},
        onSendToSomeoneElse: {}, onEditCard: {}
    )
}
