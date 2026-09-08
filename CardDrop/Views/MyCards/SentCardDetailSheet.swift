import SwiftUI

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

    private var aspectRatio: CGFloat { snapshot.orientationIsLandscape ? 3.0 / 2.0 : 2.0 / 3.0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                previewSection
                    .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 24) {
                        repliesSection
                        sendHistorySection
                    }
                    .padding(.top, 16)
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
        .task {
            frontImage   = snapshot.cardID.flatMap { draftManager.loadFront(for: $0) }
            back6x9Image = snapshot.cardID.flatMap { draftManager.loadBack6x9(for: $0) }
            guard let cardID = snapshot.cardID else { isLoading = false; return }
            async let history   = (try? CardRecipientService.fetchHistory(for: cardID)) ?? []
            async let reacts    = (try? CardReplyService.fetchReactions(for: cardID)) ?? []
            async let allReplies = (try? CardReplyService.fetchReplies(for: cardID)) ?? []
            recipients = await history
            reactions  = await reacts
            replies    = await allReplies
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

            if !reactions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reactions")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.brandBlue)

                    Text(reactions.map(\.emoji).joined())
                        .font(.system(size: 15, weight: .regular))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
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
                Text("No replies yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            } else if !replies.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(replies.enumerated()), id: \.element.id) { index, reply in
                        if index > 0 { Divider() }
                        ReplyRow(reply: reply)
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

private struct ReplyRow: View {
    let reply: CardReply

    private var dateLabel: String {
        guard let date = reply.sent_at else { return "" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let urlString = reply.reply_image_url, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().frame(maxWidth: .infinity).cornerRadius(8)
                    case .failure, .empty:
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            if let text = reply.reply_text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 15, weight: .regular))
            }
            if !dateLabel.isEmpty {
                Text(dateLabel)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
