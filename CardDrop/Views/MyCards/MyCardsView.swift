import SwiftUI

struct PostcardsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var draftManager: DraftManager
    @EnvironmentObject private var addressBook: AddressBookManager

    @State private var selectedTab: CardTab = .sent
    @State private var resumeParams: ResumeParams? = nil
    @State private var pendingResume: ResumeParams? = nil
    @State private var showCreateFlow = false
    @State private var showOTPVerification = false
    @State private var showSignInGate = false
    @State private var deleteTargetID: UUID? = nil
    @State private var repliesPanelSnapshot: PostcardDraftSnapshot? = nil
    @State private var showRepliesPanel = false
    @State private var sentDetailSnapshot: PostcardDraftSnapshot? = nil

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
                    .cornerRadius(999)
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
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.brandBlue)
                        .foregroundColor(.white)
                        .cornerRadius(999)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemBackground))
            } else if authManager.isAnonymous && authManager.nearMonthlyLimit {
                Button(action: { showSignInGate = true }) {
                    Text("Create an account for unlimited sending")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.brandBlue)
                        .foregroundColor(.white)
                        .cornerRadius(999)
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
        .sheet(item: $sentDetailSnapshot) { snapshot in
            SentCardDetailSheet(
                snapshot: snapshot,
                onSendAgain: { sendCardAgain($0) },
                onCopyAndEdit: { copyAndEditCard($0) }
            )
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
                               let newID = draftManager.save(draft: clone, currentStep: 1, status: .unsent, existingID: nil)
                               // Queue the reopen for onDisappear below, rather than a fixed
                               // delay — this fullScreenCover also has a nested preview sheet
                               // in flight, and a fixed delay can fire before both finish
                               // tearing down, silently dropping the re-present.
                               pendingResume = ResumeParams(
                                   draft: clone, step: 1,
                                   draftID: newID, originalStatus: .unsent
                               )
                               resumeParams = nil
                           })
                .environmentObject(draftManager)
                .onDisappear {
                    if let next = pendingResume {
                        pendingResume = nil
                        resumeParams = next
                    }
                }
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
        let (draft, _) = draftManager.load(snapshot)
        // Drafts always resume on "Style It" (step 1), regardless of where
        // they were saved.
        resumeParams = ResumeParams(draft: draft, step: 1, draftID: snapshot.id, originalStatus: .unsent)
    }

    // "Send Again" from SentCardDetailSheet — reopens the REAL saved card
    // (same cardID) directly at the Send step. No clone: a clone would get a
    // fresh cardID with no baked {cardID}_front.jpg on disk, so the preview/
    // upload would fall back to the raw unstyled photo instead of the actual
    // styled card that was sent.
    private func sendCardAgain(_ snapshot: PostcardDraftSnapshot) {
        let (draft, _) = draftManager.load(snapshot)
        resumeParams = ResumeParams(draft: draft, step: 5, draftID: snapshot.id, originalStatus: .sent)
    }

    // "Copy & Edit" from SentCardDetailSheet — same clone + save-as-new-draft
    // + resume-at-Style-It behavior as CreateFlowView's onEditCard for a sent card.
    private func copyAndEditCard(_ draft: PostcardDraft) {
        let clone = draft.cloneExact()
        let newID = draftManager.save(draft: clone, currentStep: 1, status: .unsent, existingID: nil)
        resumeParams = ResumeParams(draft: clone, step: 1, draftID: newID, originalStatus: .unsent)
    }

    // MARK: - Drafts

    private var unsentDrafts: [PostcardDraftSnapshot] {
        draftManager.drafts.filter { $0.status == .unsent }.sorted { $0.lastModified > $1.lastModified }
    }
    private var sentCards: [PostcardDraftSnapshot] {
        draftManager.drafts.filter { $0.status == .sent }.sorted { $0.lastModified > $1.lastModified }
    }

    @ViewBuilder
    private var draftsContent: some View {
        if unsentDrafts.isEmpty {
            ContentUnavailableView(
                "No Drafts",
                systemImage: "doc.badge.clock",
                description: Text("Start a postcard and tap Save to keep it here.")
            )
        } else {
            ScrollView {
                MasonryLayout(columns: 2, columnSpacing: 12, lineSpacing: 12) {
                    ForEach(unsentDrafts) { snapshot in
                        CardTileView(
                            snapshot: snapshot,
                            loadImage: { draftManager.thumbnail(for: snapshot) },
                            onOpen: { openDraft(snapshot) },
                            onDelete: { deleteTargetID = snapshot.id }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
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
            ScrollView {
                MasonryLayout(columns: 2, columnSpacing: 12, lineSpacing: 12) {
                    ForEach(sentCards) { snapshot in
                        CardTileView(
                            snapshot: snapshot,
                            showsReplyBadges: true,
                            loadImage: { snapshot.cardID.flatMap { draftManager.loadFront(for: $0) } },
                            onOpen: { sentDetailSnapshot = snapshot },
                            onDelete: { deleteTargetID = snapshot.id }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            .contentMargins(.bottom, 80, for: .scrollContent)
        }
    }
}

// MARK: - Masonry (Pinterest-style) layout
//
// Fixed column width, natural per-image height (from its real aspect ratio —
// landscape vs. portrait cards mixed together is what gives the staggered
// "puzzle/building block" look, no artificial randomness needed). Packs each
// item into whichever column is currently shortest.
struct MasonryLayout: Layout {
    var columns: Int
    var columnSpacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard let width = proposal.width, width > 0, !subviews.isEmpty else { return .zero }
        let columnWidth = (width - CGFloat(columns - 1) * columnSpacing) / CGFloat(columns)
        var columnHeights = [CGFloat](repeating: 0, count: columns)
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let col = columnHeights.indices.min(by: { columnHeights[$0] < columnHeights[$1] })!
            columnHeights[col] += size.height + lineSpacing
        }
        return CGSize(width: width, height: max(0, (columnHeights.max() ?? 0) - lineSpacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard !subviews.isEmpty else { return }
        let columnWidth = (bounds.width - CGFloat(columns - 1) * columnSpacing) / CGFloat(columns)
        var columnHeights = [CGFloat](repeating: 0, count: columns)
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let col = columnHeights.indices.min(by: { columnHeights[$0] < columnHeights[$1] })!
            let x = bounds.minX + CGFloat(col) * (columnWidth + columnSpacing)
            let y = bounds.minY + columnHeights[col]
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: columnWidth, height: size.height))
            columnHeights[col] += size.height + lineSpacing
        }
    }
}

// MARK: - Card tile (front-only, masonry grid)

struct CardTileView: View {
    let snapshot: PostcardDraftSnapshot
    var showsReplyBadges: Bool = false
    let loadImage: () -> UIImage?
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var image: UIImage? = nil
    @State private var reactions: [CardReaction] = []
    @State private var replyCount: Int = 0

    private var placeholderAspectRatio: CGFloat { snapshot.orientationIsLandscape ? 3.0 / 2.0 : 2.0 / 3.0 }
    // "Classic" cards bake a white border into the image itself — inset the
    // trash button further so it clears that border instead of sitting on
    // top of it; borderless cards can sit closer to the true edge.
    private var hasWhiteBorder: Bool { snapshot.borderStyle == PostcardBorder.whiteBorder.rawValue }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(Color(.secondarySystemBackground))
                    .aspectRatio(placeholderAspectRatio, contentMode: .fit)
                    .overlay(ProgressView())
            }
        }
        .clipShape(Rectangle())
        .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        // Always-visible trash button — tapping it deletes; tapping
        // anywhere else on the tile opens the card.
        .overlay(alignment: .bottomLeading) {
            Button(action: onDelete) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, hasWhiteBorder ? 18 : 8)
            .padding(.bottom, hasWhiteBorder ? 16 : 8)
        }
        // Reply/reaction summary — same corner-inset logic as the trash
        // button (mirrored to the opposite corner) so both clear a baked-in
        // "Classic" border the same way.
        .overlay(alignment: .bottomTrailing) {
            if showsReplyBadges && (!reactions.isEmpty || replyCount > 0) {
                HStack(spacing: 4) {
                    ForEach(Array(Set(reactions.map(\.emoji))).sorted().prefix(3), id: \.self) { emoji in
                        Text(emoji)
                            .font(.system(size: 13))
                            .frame(width: 24, height: 24)
                            .background(Color.white)
                            .clipShape(Circle())
                    }
                    if replyCount > 0 {
                        Text("\(replyCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.brandBlue)
                            .clipShape(Circle())
                    }
                }
                .padding(.trailing, hasWhiteBorder ? 18 : 8)
                .padding(.bottom, hasWhiteBorder ? 16 : 8)
            }
        }
        .task(id: snapshot.lastModified) {
            image = loadImage()
            guard showsReplyBadges, let cardID = snapshot.cardID else { return }
            let counts = await CardReplyService.fetchCounts(for: cardID)
            reactions = (try? await CardReplyService.fetchReactions(for: cardID)) ?? []
            replyCount = counts.replies
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
