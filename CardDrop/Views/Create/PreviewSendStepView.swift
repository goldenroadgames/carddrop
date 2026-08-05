import SwiftUI
import CoreImage.CIFilterBuiltins
import MessageUI
import Supabase

// MARK: - Preview & Send step

struct PreviewSendStepView: View {
    @ObservedObject var draft: PostcardDraft
    let filteredImage: UIImage?
    let originalStatus: CardStatus
    var onNext: () -> Void

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var draftManager: DraftManager
    @EnvironmentObject private var addressBook: AddressBookManager

    @State private var showingFront = true
    @State private var scaleX: CGFloat = 1.0
    @State private var showSubscribeGate = false
    @State private var frontRenderImage: UIImage? = nil
    @State private var backRenderImage: UIImage? = nil
    @State private var isRendering = false

    var body: some View {
        VStack(spacing: 0) {
            if showingFront {
                GeometryReader { geo in
                    let frame = cardFrame(in: geo.size, ratio: draft.orientation.aspectRatio)
                    VStack(spacing: 12) {
                        Spacer()
                        if let img = frontRenderImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(width: frame.width, height: frame.height)
                                .compositingGroup()
                                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
                                .scaleEffect(x: scaleX, y: 1)
                                .onTapGesture { flip() }
                        } else {
                            ProgressView()
                                .frame(width: frame.width, height: frame.height)
                        }
                        Text("Tap to see the back")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            } else {
                GeometryReader { geo in
                    let backFrame = cardFrame(in: geo.size, ratio: 6.0 / 4.0)
                    ScrollView {
                        VStack(spacing: 12) {
                            if let img = backRenderImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: geo.size.width - 32)
                                    .compositingGroup()
                                    .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
                                    .scaleEffect(x: scaleX, y: 1)
                                    .onTapGesture { flip() }
                            } else {
                                ProgressView()
                                    .frame(width: backFrame.width, height: backFrame.height)
                            }
                            Text("Tap to see the front")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            CardChecklistView(draft: draft)
                                .padding(.horizontal)
                                .padding(.bottom)
                        }
                        .frame(width: geo.size.width)
                        .padding(.top, 16)
                    }
                }
            }

        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: handleNextSend) {
                Label("Next: Send", systemImage: "paperplane")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.brandBlue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(uiColor: .systemBackground))
        }
        .sheet(isPresented: $showSubscribeGate) {
            SubscribeGateView(onSuccess: {
                showSubscribeGate = false
                onNext()
            })
            .environmentObject(authManager)
            .environmentObject(draftManager)
            .environmentObject(addressBook)
        }
        .onAppear {
            if originalStatus == .sent {
                frontRenderImage = draftManager.loadFront(for: draft.cardID)
                backRenderImage  = draftManager.loadBack(for: draft.cardID)
            } else {
                triggerRender()
            }
        }
    }

    private func handleNextSend() {
        onNext()
    }

    private func triggerRender() {
        guard filteredImage != nil else { return }
        Task { @MainActor in
            isRendering = true
            await Task.yield()
            renderAll()
            isRendering = false
        }
    }

    @MainActor
    private func renderAll() {
        guard let result = CardRenderer.renderAndSave(draft: draft, filteredImage: filteredImage, draftManager: draftManager) else { return }
        frontRenderImage = result.front
        backRenderImage  = result.back
    }

    private func flip() {
        withAnimation(.easeIn(duration: 0.18)) { scaleX = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            showingFront.toggle()
            withAnimation(.easeOut(duration: 0.18)) { scaleX = 1 }
        }
    }

    private func cardFrame(in available: CGSize, ratio: CGFloat) -> CGSize {
        let maxW = available.width - 48
        let maxH = available.height - 120
        if ratio >= 1 {
            let w = min(maxW, maxH * ratio)
            return CGSize(width: w, height: w / ratio)
        } else {
            let h = min(maxH, maxW / ratio)
            return CGSize(width: h * ratio, height: h)
        }
    }
}

// MARK: - Send Options sheet

struct SendOptionsView: View {
    @ObservedObject var draft: PostcardDraft
    let filteredImage: UIImage?
    let originalStatus: CardStatus
    let hasDraftSaved: Bool
    var onSaveUnsent: () -> Void
    var onSaveSent: () -> Void
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
    @State private var showPreview = false
    @State private var showStorageUpgrade = false
    @State private var showCreateAccount = false
    @State private var showVerifyEmail = false
    @State private var limitPrompt: LimitPrompt? = nil
    @State private var showEmailRecipients = false
    @State private var pendingEmailRecipients: [String] = []
    @State private var showMessageRecipients = false
    @State private var pendingMessageRecipients: [String] = []

    private struct LimitPrompt: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let isAnonymous: Bool
    }
    @EnvironmentObject private var draftManager: DraftManager
    @EnvironmentObject private var addressBook: AddressBookManager

    var body: some View {
        VStack(spacing: 0) {

            // Card thumbnail + recipient
            VStack(spacing: 6) {
                if draft.recipientName.isEmpty {
                    Text("No recipient yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("To: \(draft.recipientName)")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                }
                Button(action: { showPreview = true }) {
                    VStack(spacing: 6) {
                        if let img = teaserImage ?? filteredImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 110)
                                .cornerRadius(6)
                                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
                        }
                        Text("Tap to Preview")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.brandBlue)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)

        List {
            Section {
                    if authManager.isAnonymous {
                        Button(action: { showCreateAccount = true }) {
                            Text("Create Account - Send Real Postcards")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.brandBlue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    comingSoonRow(icon: "shippingbox", title: "Send Real Postcard",
                                  subtitle: "Printed & mailed for you")
                } header: {
                    Text("Send a Postcard")
                }

                Section {
                    sendRow(
                        icon: "envelope",
                        title: "Email",
                        subtitle: "Send as an interactive postcard",
                        color: .blue
                    ) { sendEmail() }

                    sendRow(
                        icon: "message",
                        title: "Text Message",
                        subtitle: "Send via Messages",
                        color: .green
                    ) { sendText() }

                } header: {
                    Text("Send Digitally — Free")
                }

            if !authManager.hasPermanentStorage && !authManager.isAnonymous && authManager.isEmailVerified {
                Section {
                    Button(action: { showStorageUpgrade = true }) {
                        HStack(spacing: 14) {
                            Image(systemName: "archivebox")
                                .font(.title2)
                                .foregroundColor(.purple)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cards expire after 30 days")
                                    .foregroundColor(.primary)
                                Text("Upgrade once for permanent storage — $9.99")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if draft.image != nil {
                Section {
                    sendRow(icon: "pencil", title: "Edit Card", color: .orange) { onEditCard() }
                }
            }
            }
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
        .sheet(isPresented: $showPreview) {
            CardFlipPreviewSheet(
                frontImage: draftManager.loadFront(for: draft.cardID),
                backImage: draftManager.loadBack(for: draft.cardID),
                aspectRatio: draft.orientation.aspectRatio
            )
        }
        .onAppear {
            teaserImage = draftManager.loadFront(for: draft.cardID)
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
                    teaserImage: teaserImage,
                    cardURL: result.cardURL,
                    recipientEmails: pendingEmailRecipients,
                    cardID: result.cardID,
                    onSent: {
                        Task {
                            await insertEmailRecipients(emails: pendingEmailRecipients, cardID: result.cardID)
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
            EmailRecipientsSheet(initialEmail: draft.recipientEmail) { emails in
                performEmailSend(emails: emails)
            }
        }
        .sheet(isPresented: $showMessageComposer) {
            if let result = cardSendResult {
                MessageComposeView(
                    teaserImage: teaserImage,
                    cardURL: result.cardURL,
                    recipients: pendingMessageRecipients,
                    cardID: result.cardID,
                    onSent: {
                        Task {
                            await insertMessageRecipients(recipients: pendingMessageRecipients, cardID: result.cardID)
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
            MessageRecipientsSheet(initialRecipient: draft.recipientPhone.isEmpty ? draft.recipientEmail : draft.recipientPhone) { recipients in
                performTextSend(recipients: recipients)
            }
        }
        .sheet(isPresented: $showStorageUpgrade) {
            StorageUpgradeView {
                authManager.setTierUnlimited()
            }
        }

        // Finish button
        Button(action: handleFinish) {
            Text("Finish")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.brandBlue)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)

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
            }
            .padding(.vertical, 2)
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
        .padding(.vertical, 2)
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

    private func performEmailSend(emails: [String]) {
        Task { @MainActor in
            await uploadAndSend {
                pendingEmailRecipients = emails
                if MFMailComposeViewController.canSendMail() { showMailComposer = true }
            }
        }
    }

    private func insertEmailRecipients(emails: [String], cardID: UUID) async {
        struct Row: Encodable {
            let card_id: String
            let email: String
        }
        for email in emails {
            try? await supabase
                .from("card_recipients")
                .insert(Row(card_id: cardID.uuidString, email: email))
                .execute()
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

    private func performTextSend(recipients: [String]) {
        Task { @MainActor in
            await uploadAndSend {
                pendingMessageRecipients = recipients
                if MFMessageComposeViewController.canSendText() { showMessageComposer = true }
            }
        }
    }

    private func insertMessageRecipients(recipients: [String], cardID: UUID) async {
        struct Row: Encodable {
            let card_id: String
            let email: String?
            let phone: String?
        }
        for recipient in recipients {
            let isEmail = recipient.contains("@")
            let row = Row(
                card_id: cardID.uuidString,
                email: isEmail ? recipient : nil,
                phone: isEmail ? nil : recipient
            )
            try? await supabase
                .from("card_recipients")
                .insert(row)
                .execute()
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

        teaserImage = draftManager.loadFront(for: draft.cardID)

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
    var teaserImage: UIImage?
    var cardURL: URL
    var recipientEmails: [String]
    var cardID: UUID
    var onSent: () -> Void
    var onFailed: () -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        if !recipientEmails.isEmpty { vc.setToRecipients(recipientEmails) }
        vc.setSubject("You got a CardDrop")
        let url = cardURL.absoluteString
        let base = SupabaseConfig.projectURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let imgSrc = "\(base)/storage/v1/object/public/teaser-images/\(cardID.uuidString).jpg"
        let html = """
        <html>
        <body style="font-family:-apple-system,Helvetica,sans-serif;max-width:600px;margin:0 auto;padding:20px;color:#222;">
        <p style="font-size:13px;margin-bottom:4px;text-align:center;">A <span style="font-weight:700;color:#0066FF;">Card<span style="vertical-align:-4px;">Drop</span></span> postcard is waiting for you</p>
        <p style="font-size:13px;margin-bottom:20px;text-align:center;color:#0066FF;">Tap to open it</p>
        <a href="\(url)" style="display:block;text-decoration:none;">
          <img src="\(imgSrc)" style="width:100%;max-width:560px;border-radius:10px;display:block;" />
        </a>
        <p style="margin-top:16px;font-size:14px;">
          <a href="\(url)" style="color:#0066FF;">View your postcard →</a>
        </p>
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
    var onSent: () -> Void
    var onFailed: () -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.messageComposeDelegate = context.coordinator
        if !recipients.isEmpty { vc.recipients = recipients }
        vc.body = "You got a CardDrop postcard\nTap to open it\n\n\(cardURL.absoluteString)"
        if let img = teaserImage,
           let data = PostcardHTMLGenerator.scaledForMMS(img).jpegData(compressionQuality: 0.7) {
            vc.addAttachmentData(data, typeIdentifier: "public.jpeg", filename: "postcard.jpg")
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

// MARK: - Card Flip Preview Sheet

struct CardFlipPreviewSheet: View {
    let frontImage: UIImage?
    let backImage: UIImage?
    let aspectRatio: CGFloat
    @Environment(\.dismiss) private var dismiss

    @State private var showingFront = true
    @State private var scaleX: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                let frontFrame = cardFrame(in: geo.size, ratio: aspectRatio)
                let backFrame  = cardFrame(in: geo.size, ratio: 6.0 / 4.0)
                let frame      = showingFront ? frontFrame : backFrame

                VStack(spacing: 12) {
                    Spacer()
                    Group {
                        if showingFront {
                            if let img = frontImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: frame.width, height: frame.height)
                            } else {
                                ProgressView().frame(width: frame.width, height: frame.height)
                            }
                        } else {
                            if let img = backImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: frame.width, height: frame.height)
                            } else {
                                ProgressView().frame(width: frame.width, height: frame.height)
                            }
                        }
                    }
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
                    .scaleEffect(x: scaleX, y: 1)
                    .onTapGesture { flip() }

                    Text(showingFront ? "Tap to see the back" : "Tap to see the front")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(10)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
            .padding(.top, 16)
            .padding(.leading, 16)
        }
    }

    private func flip() {
        withAnimation(.easeIn(duration: 0.18)) { scaleX = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            showingFront.toggle()
            withAnimation(.easeOut(duration: 0.18)) { scaleX = 1 }
        }
    }

    private func cardFrame(in available: CGSize, ratio: CGFloat) -> CGSize {
        let maxW = available.width - 48
        let maxH = available.height - 120
        if ratio >= 1 {
            let w = min(maxW, maxH * ratio)
            return CGSize(width: w, height: w / ratio)
        } else {
            let h = min(maxH, maxW / ratio)
            return CGSize(width: h * ratio, height: h)
        }
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

struct EmailRecipientsSheet: View {
    let initialEmail: String
    var onSend: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var emails: [String]
    @State private var pickerSlot: SlotIndex? = nil

    private let slotCount = 6

    init(initialEmail: String, onSend: @escaping ([String]) -> Void) {
        self.initialEmail = initialEmail
        self.onSend = onSend
        var arr = Array(repeating: "", count: 6)
        if !initialEmail.isEmpty { arr[0] = initialEmail }
        _emails = State(initialValue: arr)
    }

    private func isValidEmail(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return true }
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return t.range(of: pattern, options: .regularExpression) != nil
    }

    private var validEmails: [String] {
        emails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && isValidEmail($0) }
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        onSend(validEmails)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(hasInvalidEntry)
                }
            }
            .sheet(item: $pickerSlot) { slot in
                ContactPickerView { _, _, email, _ in
                    if !email.isEmpty { emails[slot.id] = email }
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
    var onSend: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recipients: [String]
    @State private var pickerSlot: SlotIndex? = nil

    private let slotCount = 6

    init(initialRecipient: String, onSend: @escaping ([String]) -> Void) {
        self.initialRecipient = initialRecipient
        self.onSend = onSend
        var arr = Array(repeating: "", count: 6)
        if !initialRecipient.isEmpty { arr[0] = initialRecipient }
        _recipients = State(initialValue: arr)
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

    private var validRecipients: [String] {
        recipients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && isValid($0) }
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        onSend(validRecipients)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(hasInvalidEntry)
                }
            }
            .sheet(item: $pickerSlot) { slot in
                ContactPickerView { _, _, email, phone in
                    let value = phone.isEmpty ? email : phone
                    if !value.isEmpty { recipients[slot.id] = value }
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
    PreviewSendStepView(draft: PostcardDraft(), filteredImage: nil, originalStatus: .unsent, onNext: {})
}
