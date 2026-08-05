import SwiftUI

struct CardRepliesPanel: View {
    let snapshot: PostcardDraftSnapshot
    let onDismiss: () -> Void

    @EnvironmentObject private var draftManager: DraftManager

    @State private var thumbnail: UIImage? = nil
    @State private var reactions: [CardReaction] = []
    @State private var replies: [CardReply] = []
    @State private var loading = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Thumbnail — landscape scaled back slightly for shadow room, portrait centered at 50% height
                    if let img = thumbnail {
                        if snapshot.orientationIsLandscape {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
                        } else {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(height: UIScreen.main.bounds.height * 0.50)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
                        }
                    } else {
                        Color(.secondarySystemBackground)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }

                    // Emoji reactions
                    if !reactions.isEmpty {
                        let emojis = reactions.map(\.emoji).joined()
                        Text(emojis)
                            .font(.title2)
                            .padding(.horizontal, 16)
                            .padding(.top, 3)
                    }

                    // Replies
                    if loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 3)
                    } else if replies.isEmpty && reactions.isEmpty {
                        Text("No replies yet.")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 3)
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(replies) { reply in
                                ReplyBubble(reply: reply)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 3)
                        .padding(.bottom, 32)
                    }
                }
            }

            // X button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.secondary)
                    .padding(12)
            }
        }
        .task {
            if let cardID = snapshot.cardID {
                thumbnail = draftManager.loadFront(for: cardID)
            }
            if let cardID = snapshot.cardID {
                async let r = (try? CardReplyService.fetchReactions(for: cardID)) ?? []
                async let p = (try? CardReplyService.fetchReplies(for: cardID)) ?? []
                reactions = await r
                replies = await p
            }
            loading = false
        }
    }
}

private struct ReplyBubble: View {
    let reply: CardReply

    private var dateLabel: String {
        guard let date = reply.sent_at else { return "" }
        let day   = Calendar.current.component(.day, from: date)
        let month = date.formatted(.dateTime.month(.abbreviated))
        let year  = String(Calendar.current.component(.year, from: date)).suffix(2)
        return String(format: "(%02d\(month)\(year))", day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Photo
            if let urlString = reply.reply_image_url, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().frame(maxWidth: .infinity).cornerRadius(8)
                    case .failure:
                        EmptyView()
                    case .empty:
                        ProgressView().frame(maxWidth: .infinity)
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            // Text with date appended
            let text = reply.reply_text ?? ""
            let display = text.isEmpty ? dateLabel : "\(text) \(dateLabel)"
            if !display.isEmpty {
                Text(display)
                    .font(.body)
            }

            Divider()
        }
    }
}
