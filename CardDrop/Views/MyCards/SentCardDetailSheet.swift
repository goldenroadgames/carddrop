import SwiftUI
import Photos

// Opens when a Sent card is tapped — a summary/hub for that card instead of
// dropping straight back into the Create flow's Send step: preview, who it
// was sent to and how, replies/reactions, and the follow-up actions (send
// again to someone new, copy the design into a fresh draft, or just close).
struct SentCardDetailSheet: View {
    let snapshot: PostcardDraftSnapshot
    let onSendAgain: (PostcardDraftSnapshot) -> Void
    let onCopyAndEdit: (PostcardDraft) -> Void

    @EnvironmentObject private var draftManager: DraftManager
    @Environment(\.dismiss) private var dismiss

    @State private var frontImage: UIImage? = nil
    @State private var back6x9Image: UIImage? = nil
    @State private var face: CardFace = .front
    @State private var scaleX: CGFloat = 1.0

    // Front -> 6x9 back -> loop, cycling forward on every tap. Only the 6x9
    // back is shown here (not the 4x6) — this sheet is meant to show off the
    // card, not compare postcard sizes.
    private enum CardFace: Int, CaseIterable {
        case front, back6x9
    }

    @State private var recipients: [CardRecipientRecord] = []
    @State private var reactions: [CardReaction] = []
    @State private var replies: [CardReply] = []
    @State private var isLoading = true
    // The server's copy expired and was removed (cards.purged_at); the card
    // can still be sent again from this device.
    @State private var expiredOnServer = false

    // This card's own "Allow replies" switch (cards.replies_enabled). The
    // profile switch overrides it; see CardReplyService.profileRepliesEnabled.
    @State private var cardRepliesEnabled = true
    @State private var openedAt: Date? = nil
    // Width of the card area (screen width less its side margins until measured).
    @State private var previewWidth: CGFloat = UIScreen.main.bounds.width - 48
    @State private var showRepliesOffChoice = false
    @State private var replyToDelete: CardReply? = nil
    @State private var repliesErrorShown = false

    private var hasWhiteBorder: Bool { snapshot.borderStyle == PostcardBorder.whiteBorder.rawValue }

    private var aspectRatio: CGFloat { snapshot.orientationIsLandscape ? 3.0 / 2.0 : 2.0 / 3.0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                previewSection
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 0) {
                        repliesSection
                        sendHistorySection
                            .padding(.top, 24)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Sent Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem("Close", placement: .cancellationAction, style: .bare) { dismiss() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar
            }
        }
        .confirmationDialog("Turn off replies for this card?", isPresented: $showRepliesOffChoice, titleVisibility: .visible) {
            Button("Hide existing replies") { setCardReplies(false, deleteExisting: false) }
            Button("Delete existing replies", role: .destructive) { setCardReplies(false, deleteExisting: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Replies and reactions on this card stop. Hidden ones come back if you turn replies on again; deleted ones are gone for good.")
        }
        .confirmationDialog(
            "Delete this reply?",
            isPresented: Binding(
                get: { replyToDelete != nil },
                set: { if !$0 { replyToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: replyToDelete
        ) { reply in
            Button("Delete", role: .destructive) { deleteReply(reply) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The reply is removed for good.")
        }
        .alert("Couldn't update replies", isPresented: $repliesErrorShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again.")
        }
        .task {
            frontImage   = snapshot.cardID.flatMap { draftManager.loadFront(for: $0) }
            back6x9Image = snapshot.cardID.flatMap { draftManager.loadBack6x9(for: $0) }
            guard let cardID = snapshot.cardID else { isLoading = false; return }
            async let history   = (try? CardRecipientService.fetchHistory(for: cardID)) ?? []
            async let reacts    = (try? CardReplyService.fetchReactions(for: cardID)) ?? []
            async let allReplies = (try? CardReplyService.fetchReplies(for: cardID)) ?? []
            async let cardFlag  = CardReplyService.cardRepliesEnabled(for: cardID)
            async let expired   = CardRecipientService.isExpiredOnServer(cardID)
            async let opened    = CardReplyService.fetchFirstOpened(for: cardID)
            recipients = await history
            reactions  = await reacts
            replies    = await allReplies
            cardRepliesEnabled = await cardFlag
            expiredOnServer = await expired
            openedAt = await opened
            isLoading  = false
        }
    }

    // MARK: - Preview

    private var currentFaceImage: UIImage? {
        switch face {
        case .front:   return frontImage
        case .back6x9: return back6x9Image
        }
    }

    // Front matches the card's own orientation; the back is always
    // landscape (6x9's 9:6 trim).
    private var currentFaceAspectRatio: CGFloat {
        face == .front ? aspectRatio : 3.0 / 2.0
    }

    // The card's long side is the width of the sheet less a margin, for
    // both orientations: a landscape face fills the width (3:2), and a portrait
    // front is as tall as that width (its long side), so the card is the same
    // physical size either way. A portrait card's area is a square so flipping
    // between its portrait front and landscape back doesn't move what is below.
    private var previewAreaRatio: CGFloat { snapshot.orientationIsLandscape ? 3.0 / 2.0 : 1.0 }

    private var previewSection: some View {
        VStack(spacing: 6) {
            // Height comes from the measured width, not from the space the stack
            // offers: the stack shares its height with the scroll view below and
            // would otherwise cap the card at about half of it.
            Color.clear
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { previewWidth = $0 }
                .frame(height: previewWidth / previewAreaRatio)
                .overlay {
                    Group {
                        if let img = currentFaceImage {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                // Share button in the corner of the FRONT only. It shares
                                // the front picture. Inset further on "Classic" cards so it
                                // clears the white border baked into the image.
                                .overlay(alignment: .bottomTrailing) {
                                    if face == .front {
                                        Button(action: sharePicture) {
                                            Image(systemName: "square.and.arrow.up")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.white)
                                                .frame(width: 32, height: 32)
                                                .background(Color.brandBlue)
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Share cardfront")
                                        .padding(.trailing, hasWhiteBorder ? 28 : 12)
                                        .padding(.bottom, hasWhiteBorder ? 24 : 12)
                                    }
                                }
                        } else {
                            Rectangle()
                                .fill(Color(.secondarySystemBackground))
                                .aspectRatio(currentFaceAspectRatio, contentMode: .fit)
                                .overlay(ProgressView())
                        }
                    }
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 5)
                    .scaleEffect(x: scaleX, y: 1)
                    .onTapGesture { flip() }
                }
                .padding(.horizontal, 24)

            VStack(spacing: 6) {
                Text("Tap to flip")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.gray)

                if let openedAt {
                    Text("Opened \(openedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.gray)
                }

                allowRepliesControl

                if !reactions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reactions")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.brandBlue)

                        Text(reactions.map(\.emoji).joined())
                            .font(.system(size: 15, weight: .regular))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Allow replies

    // The per-card switch. Meaningless while replies are off in the profile
    // (that overrides every card), so a note replaces it then.
    @ViewBuilder
    private var allowRepliesControl: some View {
        if snapshot.cardID != nil && !isLoading {
            if CardReplyService.profileRepliesEnabled {
                Button(action: toggleCardReplies) {
                    HStack(spacing: 8) {
                        Image(systemName: cardRepliesEnabled ? "checkmark.square" : "square")
                            .font(.system(size: 20))
                        Text("Allow replies")
                            .font(.system(size: 15, weight: .regular))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Replies are turned off in your Profile.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func toggleCardReplies() {
        if cardRepliesEnabled {
            // Nothing received yet: nothing to hide or delete, just turn off.
            if replies.isEmpty && reactions.isEmpty {
                setCardReplies(false, deleteExisting: false)
            } else {
                showRepliesOffChoice = true
            }
        } else {
            setCardReplies(true, deleteExisting: false)
        }
    }

    private func setCardReplies(_ enabled: Bool, deleteExisting: Bool) {
        guard let cardID = snapshot.cardID else { return }
        Task {
            let ok = await CardReplyService.setRepliesEnabled(enabled, cardID: cardID, deleteExisting: deleteExisting)
            guard ok else { repliesErrorShown = true; return }
            cardRepliesEnabled = enabled
            if enabled {
                // Hidden replies and reactions reappear.
                async let reacts     = (try? CardReplyService.fetchReactions(for: cardID)) ?? []
                async let allReplies = (try? CardReplyService.fetchReplies(for: cardID)) ?? []
                reactions = await reacts
                replies   = await allReplies
            } else {
                reactions = []
                replies   = []
            }
        }
    }

    private func deleteReply(_ reply: CardReply) {
        Task {
            if await CardReplyService.deleteReply(id: reply.id) {
                replies.removeAll { $0.id == reply.id }
            } else {
                repliesErrorShown = true
            }
        }
    }

    private func flip() {
        withAnimation(.easeIn(duration: 0.18)) { scaleX = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            let allFaces = CardFace.allCases
            let nextIndex = (allFaces.firstIndex(of: face)! + 1) % allFaces.count
            face = allFaces[nextIndex]
            withAnimation(.easeOut(duration: 0.18)) { scaleX = 1 }
        }
    }

    // MARK: - Send history

    private var sendHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Send History")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.brandBlue)
                .padding(.horizontal, 16)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
            } else if expiredOnServer {
                Text("Expired and removed from CardDrop's server. You can still send it again.")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
            } else if recipients.isEmpty {
                Text("No send record found for this card.")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recipients.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { Divider().padding(.leading, 46) }
                        HStack(spacing: 10) {
                            Image(systemName: record.modeIcon)
                                .font(.system(size: 17, weight: .regular))
                                .foregroundColor(.brandBlue)
                                .frame(width: 15)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(record.displayName)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(.primary)
                                Text("\(record.modeLabel) · \(record.created_at.formatted(.dateTime.month(.abbreviated).day().year()))")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Replies

    private var repliesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Replies")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.brandBlue)
                .padding(.horizontal, 16)

            if isLoading {
                EmptyView()
            } else if replies.isEmpty && reactions.isEmpty {
                Text(!cardRepliesEnabled || !CardReplyService.profileRepliesEnabled
                     ? "Replies are turned off."
                     : "No replies yet.")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
            } else if !replies.isEmpty {
                VStack(spacing: 0) {
                    ForEach(replies) { reply in
                        ReplyRow(
                            reply: reply,
                            onDelete: { replyToDelete = reply }
                        )
                            .padding(.vertical, 4)
                            .padding(.horizontal, 16)
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private var actionBar: some View {
        VStack(spacing: 8) {
            Button(action: {
                dismiss()
                onSendAgain(snapshot)
            }) {
                Label("Send Again", systemImage: "paperplane.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.brandBlue)
                    .foregroundColor(.white)
                    .cornerRadius(999)
            }

            Button(action: {
                let (draft, _) = draftManager.load(snapshot)
                dismiss()
                onCopyAndEdit(draft)
            }) {
                Label("Copy & Edit", systemImage: "pencil")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(999)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
    }

    // Shares the front only (the back holds the sender's private message). The
    // on-disk front is a 300-DPI print render, so downscale it to a digital size
    // (1200px long edge, same as the email thumbnail path) and share a real,
    // named JPEG file. Presented from UIKit: a SwiftUI .sheet around
    // UIActivityViewController came up blank.
    private func sharePicture() {
        guard let front = frontImage,
              let data = Self.watermarked(Self.downscaledForSharing(front)).jpegData(compressionQuality: 0.85) else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "ddMMMyy"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardDrop-front-\(formatter.string(from: Date())).jpg")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
    }

    // Draws the CardDrop wordmark in brand blue near the bottom-left corner of the
    // photo, with no background, as if it had just "dropped" into place: three
    // fainter copies are stacked above it, overlapping, the highest the faintest,
    // and the bottom ("landed") copy is fully opaque and drawn last so it stays
    // crisp. One more faint copy sits just below it, like a bounce off the floor. The margin from the left and bottom edges is the width of the
    // "Classic" white border (0.25in of a 6in long side = 4.17% of the long side)
    // plus padding, so the mark clears that border whether or not the card has
    // one. Only the shared copy is marked; the stored card stays unmarked. The web
    // card page (drawWatermark in CardView.tsx) uses the same proportions.
    private static let ghostOpacities: [CGFloat] = [0.28, 0.45, 0.62]  // highest ghost first
    private static let ghostStep: CGFloat = 0.32  // gap between copies, as a fraction of the font size
    // One faint copy just BELOW the landed one, as if it had bounced up off a floor.
    private static let bounceOffset: CGFloat = 0.18  // below the landed copy, as a fraction of the font size
    private static let bounceOpacity: CGFloat = 0.36
    // White outline around the letters: stroke width as a fraction of the font size (half of
    // it shows outside the letters, the other half is covered by the blue fill).
    private static let outlineWidth: CGFloat = 0.16

    private static func watermarked(_ image: UIImage) -> UIImage {
        let pixel = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let long = max(pixel.width, pixel.height)
        let fontSize = long * 0.04125
        let font = UIFont(name: "Inter-ExtraBold", size: fontSize) ?? UIFont.boldSystemFont(ofSize: fontSize)
        let blue = UIColor(red: 0, green: 122 / 255, blue: 1, alpha: 1)
        let dropOffset = fontSize * 0.25
        let step = fontSize * ghostStep
        // 5% of the long side: the Classic border (4.17%, about 50px on the 1200px picture)
        // plus a gap of about 10px.
        let margin = long * 0.05
        let x = margin
        // The bottom of the "p" in "Drop" sits on the bottom margin line.
        let glyphDescent = abs(font.descender) * 0.85
        let landedBaseline = pixel.height - margin - glyphDescent - dropOffset
        let cardWidth = NSAttributedString(string: "Card", attributes: [.font: font]).size().width

        func drawCopy(baseline: CGFloat, alpha: CGFloat) {
            // draw(at:) puts the top of the line box at the point: lift by the font ascender.
            let top = baseline - font.ascender
            // White outline all the way around the letters (outside them and inside
            // their holes): a stroke-only pass first (a positive stroke width draws
            // the outline only), then the blue letters on top of it.
            let outline: [NSAttributedString.Key: Any] = [
                .font: font,
                .strokeColor: UIColor.white.withAlphaComponent(alpha),
                .strokeWidth: outlineWidth * 100,  // percent of the font size
            ]
            let fill: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: blue.withAlphaComponent(alpha)]
            for attributes in [outline, fill] {
                NSAttributedString(string: "Card", attributes: attributes).draw(at: CGPoint(x: x, y: top))
                NSAttributedString(string: "Drop", attributes: attributes).draw(at: CGPoint(x: x + cardWidth, y: top + dropOffset))
            }
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: pixel, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixel))
            // Highest (faintest) ghost first, so each lower copy sits in front of the one above.
            for (k, alpha) in ghostOpacities.enumerated() {
                drawCopy(baseline: landedBaseline - CGFloat(ghostOpacities.count - k) * step, alpha: alpha)
            }
            drawCopy(baseline: landedBaseline + fontSize * bounceOffset, alpha: bounceOpacity)
            drawCopy(baseline: landedBaseline, alpha: 1)
        }
    }

    private static func downscaledForSharing(_ image: UIImage, maxDimension: CGFloat = 1200) -> UIImage {
        let long = max(image.size.width, image.size.height)
        guard long > maxDimension else { return image }
        let scale = maxDimension / long
        let newSize = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// One reply = its text (with the date).
private struct ReplyRow: View {
    let reply: CardReply
    let onDelete: () -> Void

    private var dateLabel: String {
        guard let date = reply.sent_at else { return "" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    // Non-breaking spaces inside the date so it wraps as one unbreakable
    // unit (e.g. "Sep 8, 2026") when appended to the end of reply text,
    // rather than splitting mid-date across lines.
    private var nonBreakingDateLabel: String {
        dateLabel.replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
            Group {
                if let text = reply.reply_text, !text.isEmpty {
                    if !dateLabel.isEmpty {
                        Text(text).font(.system(size: 15, weight: .regular))
                        + Text("  ").font(.system(size: 13, weight: .regular))
                        + Text(nonBreakingDateLabel).font(.system(size: 13, weight: .regular)).foregroundColor(.gray)
                    } else {
                        Text(text)
                            .font(.system(size: 15, weight: .regular))
                    }
                } else if !dateLabel.isEmpty {
                    Text(dateLabel)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete reply")
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
