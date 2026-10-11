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
    // Freshly-baked images handed directly from CreateFlowView's bakeDraftArt(),
    // when available, instead of this view re-reading the bake's disk output —
    // the disk write can still be in flight (bakeDraftArt is fire-and-forget)
    // when this view first appears, which used to show a stale preview.
    var freshFrontImage: UIImage? = nil
    var freshBackImage: UIImage? = nil
    var freshBack6x9Image: UIImage? = nil
    let originalStatus: CardStatus
    let hasDraftSaved: Bool
    var onSaveUnsent: () -> Void
    var onSaveSent: () -> Void
    var onGoToFront: () -> Void
    var onGoToBack: () -> Void
    var onFinish: () -> Void
    var onSendToSomeoneElse: () -> Void
    var onEditCard: () -> Void
    // Mirrors isSubmittingToLOB up to CreateFlowView so its toolbar Close
    // button can also block dismissal while a postcard order is mid-submit,
    // not just the Finish button below.
    var onSubmittingToLOBChanged: (Bool) -> Void = { _ in }

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
    // False on iPhones with no account in Apple's Mail app — the Email row is
    // hidden then (the Simulator always reports false, so it's exempted).
    @State private var mailAvailable = MFMailComposeViewController.canSendMail()
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingEmailRecipients: [RecipientContact] = []
    @State private var showMessageRecipients = false
    @State private var pendingMessageRecipients: [RecipientContact] = []
    @State private var showMailPostcardFlow = false
    // Free-postcard allowance (friends & family) — display only; refreshed
    // whenever the mail flow opens/closes or an order is confirmed.
    @State private var postcardAllowance: PostcardAllowance?
    @State private var showVerifyEmailForMail = false
    // True only when showCreateAccount was opened FROM the "Mail Real
    // Postcard" row (not the free-send-quota prompt) — lets its onSuccess
    // chain straight into OTP verification instead of just returning to
    // Send Options, so the user isn't asked to tap "Mail Real Postcard"
    // a second time after creating their account.
    @State private var pendingMailAfterAccountCreation = false
    @State private var showPostcardPayment = false
    @State private var pendingMailSender: SavedMailingAddress?
    @State private var pendingMailRecipient: SavedMailingAddress?
    @State private var pendingMailPrice: PostcardPriceOption?
    @State private var postcardOrderConfirmed = false
    @State private var isSubmittingToLOB = false
    @State private var showLOBSubmissionError = false
    @State private var lobSubmissionErrorMessage: String?

    #if DEBUG
    @State private var isRunningLOBTest = false
    @State private var lobTestMessage: String? = nil
    @State private var showLOBTestAlert = false
    #endif

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
            #if DEBUG
            .alert("LOB Test Export", isPresented: $showLOBTestAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(lobTestMessage ?? "")
            }
            #endif
        .onAppear {
            SuspensionMonitor.trigger()
            mailAvailable = MFMailComposeViewController.canSendMail()
            teaserImage       = freshFrontImage  ?? draftManager.loadFront(for: draft.cardID)
            backRenderImage   = freshBackImage   ?? draftManager.loadBack(for: draft.cardID)
            back6x9RenderImage = freshBack6x9Image ?? draftManager.loadBack6x9(for: draft.cardID)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { mailAvailable = MFMailComposeViewController.canSendMail() }
        }
        // bakeDraftArt() is fire-and-forget, so its render can still be
        // running when this view first appears (see freshBackImage doc
        // comment above) — pick up the result once it lands instead of
        // staying on whatever onAppear read (stale disk file, or nil).
        .onChange(of: freshFrontImage) { _, newImage in
            if let newImage { teaserImage = newImage }
        }
        .onChange(of: freshBackImage) { _, newImage in
            if let newImage { backRenderImage = newImage }
        }
        .onChange(of: freshBack6x9Image) { _, newImage in
            if let newImage { back6x9RenderImage = newImage }
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
                    cardURL: result.cardURL,
                    thumbnailURL: authManager.currentUserID.flatMap {
                        URL(string: "\(Secrets.supabaseURL)/storage/v1/object/public/card-images/\($0.lowercased())/\(result.cardID.uuidString.lowercased())_thumb.jpg")
                    },
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
        .sheet(isPresented: $showVerifyEmailForMail) {
            OTPVerificationView(
                onSuccess: {
                    showVerifyEmailForMail = false
                    showMailPostcardFlow = true
                },
                onCancel: { showVerifyEmailForMail = false }
            )
            .environmentObject(authManager)
            .environmentObject(draftManager)
            .environmentObject(addressBook)
        }
        .task(id: showMailPostcardFlow) { postcardAllowance = await PostcardOrderService.fetchAllowance() }
        .task(id: postcardOrderConfirmed) { postcardAllowance = await PostcardOrderService.fetchAllowance() }
        .sheet(isPresented: $showMailPostcardFlow) {
            PostcardAddressStepView(allowance: postcardAllowance) { sender, recipient, price in
                pendingMailSender = sender
                pendingMailRecipient = recipient
                pendingMailPrice = price
                showMailPostcardFlow = false
                showPostcardPayment = true
            }
        }
        .sheet(isPresented: $showPostcardPayment) {
            if let pendingMailSender, let pendingMailRecipient, let pendingMailPrice {
                PostcardPaymentSheet(
                    cardID: draft.cardID,
                    sender: pendingMailSender,
                    recipient: pendingMailRecipient,
                    price: pendingMailPrice
                ) { success, orderID in
                    showPostcardPayment = false
                    if success, let orderID {
                        Task { await submitPostcardOrder(orderID: orderID, size: pendingMailPrice.size) }
                    }
                }
            }
        }
        .alert("Postcard Ordered", isPresented: $postcardOrderConfirmed) {
            // Just dismiss the alert — stay on Send Options so the user can
            // send to another recipient (digitally or by mail) before
            // choosing to tap Finish themselves.
            Button("OK") {}
        } message: {
            Text("Your postcard is on its way to being printed and mailed.")
        }
        .alert("Postcard Not Sent", isPresented: $showLOBSubmissionError, presenting: lobSubmissionErrorMessage) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
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
                        ) {
                            pendingMailAfterAccountCreation = true
                            showCreateAccount = true
                        }
                    } else if !authManager.isEmailVerified {
                        // Physical mail involves real payment and a real mailing
                        // address — unlike digital sends, which allow a small
                        // free quota before verification is required, this one
                        // is gated up front, every time.
                        sendRow(
                            icon: "photo",
                            title: "Mail Real Postcard",
                            subtitle: "Verify Your Email to Mail Real Postcards",
                            color: .brandBlue
                        ) { showVerifyEmailForMail = true }
                    } else {
                        sendRow(
                            icon: "photo",
                            title: "Mail Real Postcard",
                            subtitle: (postcardAllowance?.remaining ?? 0) > 0
                                ? "Print & mail – \(postcardAllowance?.remaining ?? 0) free left this month"
                                : "Printed & mailed for you",
                            color: .brandBlue
                        ) { showMailPostcardFlow = true }
                    }
                }
                .padding(.horizontal, 16)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

                #if DEBUG
                VStack(spacing: 0) {
                    sendRow(icon: "hammer", title: "Test LOB Export (4x6)",
                            subtitle: isRunningLOBTest ? "Rendering + uploading…" : "Debug only — not a real send",
                            color: .orange) { runLOBTest(size: .fourBySix) }
                    Divider().padding(.leading, 66)
                    sendRow(icon: "hammer", title: "Test LOB Export (6x9)",
                            subtitle: isRunningLOBTest ? "Rendering + uploading…" : "Debug only — not a real send",
                            color: .orange) { runLOBTest(size: .sixByNine) }
                }
                .disabled(isRunningLOBTest)
                .padding(.horizontal, 16)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
                #endif

                // Send Digitally — anchored directly above Finish rather than
                // scrolling with the rest of the List.
                Text("Send Digitally — Free")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.brandBlue)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 16)

                VStack(spacing: 0) {
                    if mailAvailable || isRunningInSimulator {
                        sendRow(
                            icon: "envelope",
                            title: "Email",
                            subtitle: "Send as an interactive postcard",
                            color: .blue
                        ) { sendEmail() }
                        .padding(.horizontal, 16)

                        Divider().padding(.leading, 66)
                    }

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

                // Finish button — disabled while a postcard order is still being
                // submitted to LOB, so the user can't dismiss (and lose track of
                // whether it worked) before that result comes back.
                Button(action: handleFinish) {
                    if isSubmittingToLOB {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.brandBlue.opacity(0.5))
                            .cornerRadius(999)
                    } else {
                        Text("Finish")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.brandBlue)
                            .foregroundColor(.white)
                            .cornerRadius(999)
                    }
                }
                .disabled(isSubmittingToLOB)
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
                    if prompt.isAnonymous {
                        pendingMailAfterAccountCreation = false
                        showCreateAccount = true
                    }
                    else { showVerifyEmail = true }
                },
                secondaryButton: .cancel(Text("No")) {
                    handleFinish()
                }
            )
        }
        .sheet(isPresented: $showCreateAccount) {
            SubscribeGateView(onSuccess: {
                showCreateAccount = false
                if pendingMailAfterAccountCreation {
                    pendingMailAfterAccountCreation = false
                    showVerifyEmailForMail = true
                }
            })
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
        .overlay {
            // Blocking, non-dismissible — same window the Finish/Close
            // buttons are disabled for (see onSubmittingToLOBChanged).
            if isSubmittingToLOB {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Submitting your postcard order…")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 48)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSubmittingToLOB)
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
                performEmailSend(entries: [])
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
        if entries.isEmpty { await insertSendLog(method: "email", cardID: cardID); return }
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

    // Mirrors insertEmailRecipients/insertMessageRecipients — without this,
    // a physical order's recipient never lands in card_recipients, so Send
    // History (which reads that table, see CardRecipientService) shows
    // nothing even though the card was successfully mailed.
    // CardRecipientRecord.modeLabel/modeIcon already special-case
    // send_method == "postcard" ("Mailed Postcard") — nothing wrote that
    // value until now.
    private func insertPostcardRecipient(_ recipient: SavedMailingAddress) async {
        struct Row: Encodable {
            let card_id: String
            let first_name: String?
            let last_name: String?
            let street: String?
            let city: String?
            let state: String?
            let zip: String?
            let country: String?
            let send_method: String
        }
        let row = Row(
            card_id: draft.cardID.uuidString,
            first_name: recipient.firstName,
            last_name: recipient.lastName,
            street: recipient.street,
            city: recipient.city,
            state: recipient.state,
            zip: recipient.zip,
            country: recipient.country,
            send_method: "postcard"
        )
        try? await supabase
            .from("card_recipients")
            .insert(row)
            .execute()
    }

    private func sendText() {
        guard !isSending else { return }
        guard draft.image != nil else { showMissingPhotoAlert = true; return }
        Task { @MainActor in
            do {
                try await CardUploadService.checkSendLimits()
                performTextSend(entries: [])
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

    /// The native Mail/Messages composers don't report who a card was sent to,
    /// so with no recipients collected up front the log row records only the
    /// method, time (created_at) and the To-field nickname, if any.
    private func insertSendLog(method: String, cardID: UUID) async {
        struct Row: Encodable {
            let card_id: String
            let nickname: String?
            let send_method: String
        }
        let nickname = draft.recipientNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let row = Row(card_id: cardID.uuidString,
                      nickname: nickname.isEmpty ? nil : nickname,
                      send_method: method)
        try? await supabase.from("card_recipients").insert(row).execute()
    }

    private func insertMessageRecipients(entries: [RecipientContact], cardID: UUID) async {
        if entries.isEmpty { await insertSendLog(method: "text", cardID: cardID); return }
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

    // Runs after a physical-mail order's payment is confirmed 'paid':
    // renders the size-correct front/back pair (rendering only happens
    // on-device, so this can't be done in the submit-to-lob edge function),
    // uploads it, then hands the resulting URLs to submit-to-lob. The order
    // itself already reached 'paid' before this runs, so a failure here
    // doesn't lose the payment — it just leaves the order retriable later
    // (see the planned pending-order reconciliation job).
    private func submitPostcardOrder(orderID: String, size: PostcardSize) async {
        isSubmittingToLOB = true
        onSubmittingToLOBChanged(true)
        defer {
            isSubmittingToLOB = false
            onSubmittingToLOBChanged(false)
        }

        let sizeLabel = size == .fourBySix ? "4x6" : "6x9"
        do {
            // A card's content is immutable once created, so if this exact
            // cardID+size was already rendered/uploaded (e.g. ordering a
            // second physical copy of the same design), reuse it rather
            // than redundantly re-rendering and overwriting it.
            let urls: (frontURL: URL, backURL: URL)
            if let existing = try await CardUploadService.existingLOBExportURLs(cardID: draft.cardID, sizeLabel: sizeLabel) {
                urls = existing
            } else {
                let lobSize: CardRenderer.LOBPostcardSize = size == .fourBySix ? .fourBySix : .sixByNine
                guard let export = CardRenderer.renderLOBTestExport(draft: draft, filteredImage: filteredImage, size: lobSize),
                      let frontData = export.front.jpegData(compressionQuality: 0.88),
                      let backData = export.back.jpegData(compressionQuality: 0.88) else {
                    lobSubmissionErrorMessage = "Sorry, we could not mail your postcard - your credit card was not charged. Please try again, or contact support if this keeps happening."
                    showLOBSubmissionError = true
                    return
                }
                urls = try await CardUploadService.uploadLOBTestExport(
                    cardID: draft.cardID, frontData: frontData, backData: backData, sizeLabel: sizeLabel
                )
            }
            // The physical postcard's back-of-card QR links to /card/{cardID}
            // on the webapp, which reads card-images/{senderID}/{cardID}.jpg
            // and _back.jpg — the DIGITAL-resolution images, not the LOB
            // print export above. A card mailed without ever being sent
            // digitally first has never had these uploaded, so that link
            // 404s unless we upload them here too. Idempotent (upsert), so
            // safe to run even when the LOB export itself was reused above.
            if let frontData = draftManager.loadFrontData(for: draft.cardID),
               let backData = draftManager.loadBackData(for: draft.cardID) {
                let back6x9Data = draftManager.loadBack6x9Data(for: draft.cardID)
                try await CardUploadService.uploadDigitalCardImages(
                    cardID: draft.cardID, frontData: frontData, backData: backData, back6x9Data: back6x9Data,
                    beforeImage: draft.image
                )
            }
            _ = try await PostcardOrderService.submitToLOB(
                orderID: orderID, frontImageURL: urls.frontURL, backImageURL: urls.backURL
            )
            if let recipient = pendingMailRecipient {
                await insertPostcardRecipient(recipient)
            }
            // Mirrors the digital-send paths (onSaveSent then onFinish) —
            // onFinish is deferred to the alert's OK button below so the
            // user sees the confirmation before the flow dismisses.
            // hasSent must also flip here: handleFinish() (Finish button)
            // calls onSaveUnsent() whenever !hasSent, and hasSent was
            // previously only ever set true by the digital-send paths —
            // without this, tapping Finish after a physical-only send
            // immediately flipped the draft right back to .unsent.
            hasSent = true
            onSaveSent()
            postcardOrderConfirmed = true
        } catch {
            let genericMessage = "Sorry, we could not mail your postcard - your credit card was not charged. Please try again, or contact support if this keeps happening."
            lobSubmissionErrorMessage = "\(genericMessage)\n\n\(error.localizedDescription)"
            showLOBSubmissionError = true
        }
    }

    #if DEBUG
    // Debug-only: renders + uploads a fresh LOB-shaped front/back pair on
    // demand for manual testing against LOB's dashboard/API. Not part of the
    // regular send flow — nothing here is cached or reused by a real send.
    private func runLOBTest(size: CardRenderer.LOBPostcardSize) {
        isRunningLOBTest = true
        Task { @MainActor in
            defer { isRunningLOBTest = false }
            guard let export = CardRenderer.renderLOBTestExport(draft: draft, filteredImage: filteredImage, size: size),
                  let frontData = export.front.jpegData(compressionQuality: 0.88),
                  let backData = export.back.jpegData(compressionQuality: 0.88) else {
                lobTestMessage = "Render failed."
                showLOBTestAlert = true
                return
            }
            let sizeLabel = size == .fourBySix ? "4x6" : "6x9"
            do {
                let urls = try await CardUploadService.uploadLOBTestExport(
                    cardID: draft.cardID, frontData: frontData, backData: backData, sizeLabel: sizeLabel
                )
                lobTestMessage = "Uploaded \(sizeLabel):\nFront: \(urls.frontURL.absoluteString)\nBack: \(urls.backURL.absoluteString)"
            } catch {
                lobTestMessage = "Upload failed: \(error.localizedDescription)"
            }
            showLOBTestAlert = true
        }
    }
    #endif

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
                frontIsPortrait: draft.orientation == .portrait,
                frontInkMessage: frontInk,
                backInkMessage: backInk,
                senderNickname: draft.senderNickname.isEmpty ? nil : draft.senderNickname,
                recipientNickname: draft.recipientNickname.isEmpty ? nil : draft.recipientNickname,
                recipientName: draft.recipientName.isEmpty ? nil : draft.recipientName,
                recipientPhone: draft.recipientPhone.isEmpty ? nil : draft.recipientPhone,
                recipientEmail: draft.recipientEmail.isEmpty ? nil : draft.recipientEmail,
                messagePreview: String(draft.message.prefix(100)),
                designFeatures: draft.designFeatureSummary(),
                beforeImage: draft.image
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
    var cardURL: URL
    /// Public 600px front thumbnail (card-images/.../{cardID}_thumb.jpg).
    var thumbnailURL: URL? = nil
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

        let url = cardURL.absoluteString
        let imageHTML = thumbnailURL.map {
            "<p style=\"margin:0 0 14px;\"><a href=\"\(url)\"><img src=\"\($0.absoluteString)\" alt=\"Your CardDrop\" style=\"width:100%;max-width:600px;height:auto;border-radius:10px;border:0;\"></a></p>"
        } ?? ""
        let html = """
        <html>
        <body style="font-family:-apple-system,Helvetica,sans-serif;max-width:600px;margin:0 auto;padding:20px;color:#222;text-align:center;">
        \(imageHTML)
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
        vc.body = "\(from) sent a CardDrop\nTap to open it.\n\(cardURL.absoluteString)"
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
        onSaveUnsent: {}, onSaveSent: {}, onGoToFront: {}, onGoToBack: {}, onFinish: {},
        onSendToSomeoneElse: {}, onEditCard: {}
    )
}
