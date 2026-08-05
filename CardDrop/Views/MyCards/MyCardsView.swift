import SwiftUI

struct PostcardsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var draftManager: DraftManager
    @EnvironmentObject private var addressBook: AddressBookManager

    @State private var selectedTab: CardTab = .sent
    @State private var resumeParams: ResumeParams? = nil
    @State private var showCreateFlow = false
    @State private var showOTPVerification = false
    @State private var showSignInGate = false
    @State private var deleteTargetID: UUID? = nil
    @State private var repliesPanelSnapshot: PostcardDraftSnapshot? = nil
    @State private var showRepliesPanel = false

    enum CardTab { case sent, drafts }

    struct ResumeParams: Identifiable {
        let id = UUID()
        let draft: PostcardDraft
        let step: Int
        let draftID: UUID?
        let originalStatus: CardStatus
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Button(action: { showCreateFlow = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                        Text("Create a Postcard")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.brandBlue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)

                Picker("", selection: $selectedTab) {
                    Text("Sent").tag(CardTab.sent)
                    Text("Drafts").tag(CardTab.drafts)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .onAppear {
                    if sentCards.isEmpty && !unsentDrafts.isEmpty {
                        selectedTab = .drafts
                    }
                }

                switch selectedTab {
                case .sent:
                    sentContent
                case .drafts:
                    draftsContent
                }
            }
            .navigationBarHidden(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDrafts)) { _ in
            selectedTab = .drafts
        }
        .sheet(isPresented: $showOTPVerification) {
            OTPVerificationView()
                .environmentObject(authManager)
                .environmentObject(draftManager)
                .environmentObject(addressBook)
        }
        .sheet(isPresented: $showSignInGate) {
            SubscribeGateView(onSuccess: { showSignInGate = false })
                .environmentObject(authManager)
                .environmentObject(draftManager)
                .environmentObject(addressBook)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !authManager.isAnonymous && !authManager.isEmailVerified && authManager.nearMonthlyLimit {
                Button(action: { showOTPVerification = true }) {
                    Text("Verify your email for unlimited sending")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.brandBlue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemBackground))
            } else if authManager.isAnonymous && authManager.nearMonthlyLimit {
                Button(action: { showSignInGate = true }) {
                    Text("Create an account for unlimited sending")
                        .fontWeight(.semibold)
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
        }
        .fullScreenCover(isPresented: $showCreateFlow) {
            CreateFlowView()
                .environmentObject(draftManager)
        }
        .overlay(alignment: .leading) {
            if showRepliesPanel, let snap = repliesPanelSnapshot {
                CardRepliesPanel(snapshot: snap, onDismiss: {
                    withAnimation(.easeInOut(duration: 0.28)) { showRepliesPanel = false }
                })
                .environmentObject(draftManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.move(edge: .leading))
                .zIndex(10)
            }
        }
        .fullScreenCover(item: $resumeParams) { params in
            CreateFlowView(resuming: params.draft, step: params.step, draftID: params.draftID,
                           originalStatus: params.originalStatus,
                           onSendToSomeoneElse: { clone in
                               resumeParams = nil
                               DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                   resumeParams = ResumeParams(
                                       draft: clone, step: 5,
                                       draftID: nil, originalStatus: .unsent
                                   )
                               }
                           },
                           onEditCard: { clone in
                               let newID = draftManager.save(draft: clone, currentStep: 0, status: .unsent, existingID: nil)
                               resumeParams = nil
                               DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                   resumeParams = ResumeParams(
                                       draft: clone, step: 0,
                                       draftID: newID, originalStatus: .unsent
                                   )
                               }
                           })
                .environmentObject(draftManager)
        }
        .alert("Delete Card?", isPresented: Binding(
            get: { deleteTargetID != nil },
            set: { if !$0 { deleteTargetID = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = deleteTargetID {
                    let cardID = draftManager.drafts.first(where: { $0.id == id })?.cardID
                    draftManager.delete(id)
                    if let cardID {
                        Task { await CardDeleteService.delete(cardID: cardID) }
                    }
                }
                deleteTargetID = nil
            }
            Button("Cancel", role: .cancel) { deleteTargetID = nil }
        } message: {
            Text("This permanently deletes the card, all replies, and the shared link. Cannot be undone.")
        }
    }

    // MARK: - Actions

    private func openDraft(_ snapshot: PostcardDraftSnapshot) {
        let (draft, savedStep) = draftManager.load(snapshot)
        let step = savedStep >= 2 ? 2 : savedStep
        resumeParams = ResumeParams(draft: draft, step: step, draftID: snapshot.id, originalStatus: .unsent)
    }

    private func editSentCard(_ snapshot: PostcardDraftSnapshot) {
        let (draft, _) = draftManager.load(snapshot)
        resumeParams = ResumeParams(draft: draft, step: 7, draftID: snapshot.id, originalStatus: .sent)
    }

    // MARK: - Row action buttons

    @ViewBuilder
    private func actionButtons(onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Button("Edit", action: onEdit)
                .buttonStyle(.plain)
                .font(.system(size: 17).weight(.medium))
                .foregroundColor(.accentColor)
                .frame(width: 72)
                .padding(.vertical, 5)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(6)

            Button("Delete", action: onDelete)
                .buttonStyle(.plain)
                .font(.system(size: 17).weight(.medium))
                .foregroundColor(.red)
                .frame(width: 72)
                .padding(.vertical, 5)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(6)
        }
    }

    // MARK: - Drafts

    private var unsentDrafts: [PostcardDraftSnapshot] { draftManager.drafts.filter { $0.status == .unsent } }
    private var sentCards:    [PostcardDraftSnapshot] { draftManager.drafts.filter { $0.status == .sent } }

    @ViewBuilder
    private var draftsContent: some View {
        if unsentDrafts.isEmpty {
            ContentUnavailableView(
                "No Drafts",
                systemImage: "doc.badge.clock",
                description: Text("Start a postcard and tap Save to keep it here.")
            )
        } else {
            List {
                ForEach(unsentDrafts) { snapshot in
                    CardRowView(
                        snapshot: snapshot,
                        onEdit:   { openDraft(snapshot) },
                        onDelete: { deleteTargetID = snapshot.id }
                    )
                    .environmentObject(draftManager)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .listStyle(.plain)
            .contentMargins(.bottom, 80, for: .scrollContent)
        }
    }

    // MARK: - Sent

    @ViewBuilder
    private var sentContent: some View {
        if sentCards.isEmpty {
            ContentUnavailableView(
                "No Sent Cards",
                systemImage: "paperplane",
                description: Text("Cards you send will appear here.")
            )
        } else {
            List {
                ForEach(sentCards) { snapshot in
                    SentCardRow(
                        snapshot: snapshot,
                        onEdit: { editSentCard(snapshot) },
                        onDelete: { deleteTargetID = snapshot.id },
                        onShowReplies: {
                            repliesPanelSnapshot = snapshot
                            withAnimation(.easeInOut(duration: 0.28)) { showRepliesPanel = true }
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .listStyle(.plain)
            .contentMargins(.bottom, 80, for: .scrollContent)
        }
    }
}

// MARK: - Sent card row (3-column layout)

struct SentCardRow: View {
    let snapshot: PostcardDraftSnapshot
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onShowReplies: () -> Void

    @EnvironmentObject private var draftManager: DraftManager
    @State private var thumbnail: UIImage? = nil
    @State private var reactionEmojis: String = ""
    @State private var replyCount: Int = 0

    private var dateLabel: String {
        let d = snapshot.lastModified
        let day   = Calendar.current.component(.day, from: d)
        let month = d.formatted(.dateTime.month(.abbreviated))
        let year  = String(Calendar.current.component(.year, from: d)).suffix(2)
        return String(format: "%02d\(month)\(year)", day)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {

            // Thumbnail
            Group {
                if let img = thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width:  snapshot.orientationIsLandscape ? 225 : 150,
                            height: snapshot.orientationIsLandscape ? 150 : 225
                        )
                        .rotationEffect(snapshot.orientationIsLandscape ? .degrees(0) : .degrees(-90))
                } else {
                    Color(.secondarySystemBackground)
                        .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                }
            }
            .frame(width: 225, height: 150)
            .cornerRadius(4)
            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            .onTapGesture { onEdit() }

            // Right side: replies+emojis, open/delete, date
            VStack(alignment: .leading, spacing: 8) {
                if !reactionEmojis.isEmpty {
                    Text(reactionEmojis)
                        .font(.system(size: 22))
                        .lineLimit(1)
                }
                if replyCount > 0 {
                    Button(action: onShowReplies) {
                        Text(replyCount == 1 ? "1 reply" : "\(replyCount) replies")
                            .font(.system(size: 22).weight(.medium))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 6) {
                    Button("Open", action: onEdit)
                        .buttonStyle(.plain)
                        .font(.system(size: 22).weight(.medium))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(6)
                    Button("Delete", action: onDelete)
                        .buttonStyle(.plain)
                        .font(.system(size: 22).weight(.medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(6)
                }
                Text(dateLabel)
                    .font(.system(size: 16).weight(.medium))
                    .foregroundColor(.brandBlue.opacity(0.85))
                    .padding(.leading, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {}
        .task(id: snapshot.lastModified) {
            if let cardID = snapshot.cardID {
                thumbnail = draftManager.loadFront(for: cardID)
            }
            if let cardID = snapshot.cardID {
                let counts = await CardReplyService.fetchCounts(for: cardID)
                let reactions = (try? await CardReplyService.fetchReactions(for: cardID)) ?? []
                reactionEmojis = reactions.map(\.emoji).joined()
                replyCount = counts.replies
            }
        }
    }
}

// MARK: - Draft card row

struct CardRowView: View {
    let snapshot: PostcardDraftSnapshot
    let onEdit: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject private var draftManager: DraftManager
    @State private var thumbnail: UIImage? = nil

    private var dateLabel: String {
        let d = snapshot.lastModified
        let day   = Calendar.current.component(.day, from: d)
        let month = d.formatted(.dateTime.month(.abbreviated))
        let year  = String(Calendar.current.component(.year, from: d)).suffix(2)
        let time  = d.formatted(.dateTime.hour().minute())
        return String(format: "%02d\(month)\(year) \(time)", day)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let img = thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width:  snapshot.orientationIsLandscape ? 225 : 150,
                            height: snapshot.orientationIsLandscape ? 150 : 225
                        )
                        .rotationEffect(snapshot.orientationIsLandscape ? .degrees(0) : .degrees(-90))
                } else {
                    Color(.secondarySystemBackground)
                        .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                }
            }
            .frame(width: 225, height: 150)
            .cornerRadius(4)
            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            .onTapGesture { onEdit() }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Button("Edit", action: onEdit)
                        .buttonStyle(.plain)
                        .font(.system(size: 22).weight(.medium))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(6)
                    Button("Delete", action: onDelete)
                        .buttonStyle(.plain)
                        .font(.system(size: 22).weight(.medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(6)
                }
                Text(dateLabel)
                    .font(.system(size: 16).weight(.medium))
                    .foregroundColor(.brandBlue.opacity(0.85))
                    .padding(.leading, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .task(id: snapshot.lastModified) {
            thumbnail = draftManager.thumbnail(for: snapshot)
        }
    }
}

extension Notification.Name {
    static let navigateToDrafts = Notification.Name("carddrop.navigateToDrafts")
}

#Preview {
    PostcardsView()
        .environmentObject(DraftManager())
}
