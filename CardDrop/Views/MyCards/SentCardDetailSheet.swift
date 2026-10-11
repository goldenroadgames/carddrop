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
    @State private var selectedPhoto: PhotoRef? = nil

    // This card's own "Allow replies" switch (cards.replies_enabled). The
    // profile switch overrides it; see CardReplyService.profileRepliesEnabled.
    @State private var cardRepliesEnabled = true
    @State private var showRepliesOffChoice = false
    @State private var replyToDelete: CardReply? = nil
    @State private var repliesErrorShown = false

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
        .fullScreenCover(item: $selectedPhoto) { photo in
            ReplyPhotoViewer(url: photo.url)
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
            Text("The reply and its photo are removed for good.")
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
            recipients = await history
            reactions  = await reacts
            replies    = await allReplies
            cardRepliesEnabled = await cardFlag
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

    private var previewSection: some View {
        VStack(spacing: 6) {
            Group {
                if let img = currentFaceImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color(.secondarySystemBackground))
                        .aspectRatio(currentFaceAspectRatio, contentMode: .fit)
                        .overlay(ProgressView())
                }
            }
            .frame(maxHeight: 340)
            .compositingGroup()
            .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 5)
            .scaleEffect(x: scaleX, y: 1)
            .onTapGesture { flip() }

            Text("Tap to flip")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.gray)

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
            } else if recipients.isEmpty {
                Text("No send record found for this card.")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            } else if !replies.isEmpty {
                VStack(spacing: 0) {
                    ForEach(replies) { reply in
                        ReplyRow(
                            reply: reply,
                            onPhotoTap: { url in selectedPhoto = PhotoRef(url: url) },
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
}

private struct PhotoRef: Identifiable {
    let id = UUID()
    let url: URL
}

// Full-screen photo-reply viewer — tap a reply's photo in the "Replies"
// list to land here, with a save-to-camera-roll action. Downloads its own
// UIImage (rather than reusing AsyncImage's SwiftUI Image) since saving to
// Photos needs the raw UIImage, not a renderable view.
private struct ReplyPhotoViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage? = nil
    @State private var isSaving = false
    @State private var statusMessage: String? = nil

    var body: some View {
        ZStack {
            Color(white: 0.93).ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }

            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 45, height: 45)
                            .background(Color.brandBlue)
                            .clipShape(Circle())
                    }
                    Spacer()
                    if image != nil {
                        Button(action: save) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 45, height: 45)
                                .background(Color.brandBlue)
                                .clipShape(Circle())
                        }
                        .disabled(isSaving)
                    }
                }
                .padding(16)

                Spacer()

                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.brandBlue)
                        .cornerRadius(999)
                        .padding(.bottom, 24)
                }
            }
        }
        .task {
            guard image == nil, let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            image = UIImage(data: data)
        }
    }

    private func save() {
        guard let image, !isSaving else { return }
        isSaving = true
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    isSaving = false
                    showStatus("Enable Photos access in Settings to save")
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { success, _ in
                    DispatchQueue.main.async {
                        isSaving = false
                        showStatus(success ? "Saved to Photos" : "Couldn't save photo")
                    }
                }
            }
        }
    }

    private func showStatus(_ text: String) {
        statusMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if statusMessage == text { statusMessage = nil }
        }
    }
}

// One reply = its text (with the date) and, if it came with one, its photo
// right below the text. Tapping the photo opens the full-screen viewer.
private struct ReplyRow: View {
    let reply: CardReply
    let onPhotoTap: (URL) -> Void
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

    private var photoURL: URL? {
        reply.reply_image_url.flatMap { URL(string: $0) }
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

            if let url = photoURL {
                Button(action: { onPhotoTap(url) }) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            // Full photo, own aspect ratio, no crop.
                            image.resizable().aspectRatio(contentMode: .fit)
                                .cornerRadius(8)
                        case .failure:
                            Color(.secondarySystemBackground)
                                .frame(height: 110)
                                .cornerRadius(8)
                        default:
                            Color(.secondarySystemBackground)
                                .frame(height: 110)
                                .overlay(ProgressView())
                                .cornerRadius(8)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 220, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
