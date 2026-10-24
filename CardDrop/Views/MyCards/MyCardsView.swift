import SwiftUI

struct PostcardsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var draftManager: DraftManager
    @EnvironmentObject private var addressBook: AddressBookManager

    @State private var selectedTab: CardTab = .sent
    @State private var resumeParams: ResumeParams? = nil
    @State private var pendingResume: ResumeParams? = nil
    @State private var showCreateFlow = false
    @State private var showOTPVerification = false
    @State private var showSignInGate = false
    @State private var deleteTargetID: UUID? = nil
    @State private var showDeleteFailed = false
    @State private var noticeTitle = ""
    @State private var noticeMessage = ""
    @State private var showNotice = false
    @State private var repliesPanelSnapshot: PostcardDraftSnapshot? = nil
    @State private var showRepliesPanel = false
    @State private var sentDetailSnapshot: PostcardDraftSnapshot? = nil
    // Latest reaction/reply time per sent card; the gallery orders by the newer of this and lastModified.
    @State private var lastActivity: [UUID: Date] = [:]
    @ObservedObject private var push = PushNotificationManager.shared

    enum CardTab { case sent, drafts, rings }

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
                Button(action: {
                    SuspensionMonitor.trigger()
                    showCreateFlow = true
                }) {
                    HStack {
                        Image("SendIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 32)
                        Text("Send a Postcard")
                            .font(.headline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.brandBlue)
                    .foregroundColor(.white)
                    .cornerRadius(999)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 4)

                Picker("", selection: $selectedTab) {
                    Text("Sent").tag(CardTab.sent)
                    Text("Drafts").tag(CardTab.drafts)
                    Text("Rings").tag(CardTab.rings)
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
                case .rings:
                    ringsContent
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
                        .font(.system(size: 21, weight: .semibold))
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
                        .font(.system(size: 21, weight: .semibold))
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
                                       draft: clone, step: 4,
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
                if let id = deleteTargetID,
                   let snapshot = draftManager.drafts.first(where: { $0.id == id }) {
                    if snapshot.status == .sent, let cardID = snapshot.cardID {
                        // Sent card: the shared link stays live until the server
                        // confirms, so keep the local copy until then.
                        Task {
                            if await CardDeleteService.delete(cardID: cardID) {
                                draftManager.delete(id)
                            } else {
                                showDeleteFailed = true
                            }
                        }
                    } else {
                        // Draft: delete locally right away; clean up any partial
                        // server upload in the background.
                        let cardID = snapshot.cardID
                        draftManager.delete(id)
                        if let cardID {
                            Task { _ = await CardDeleteService.delete(cardID: cardID) }
                        }
                    }
                }
                deleteTargetID = nil
            }
            Button("Cancel", role: .cancel) { deleteTargetID = nil }
        } message: {
            Text("This permanently deletes the card, all replies, and the shared link. Cannot be undone.")
        }
        .alert("Couldn't Delete Card", isPresented: $showDeleteFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again. The card and its shared link are still active.")
        }
        .alert(noticeTitle, isPresented: $showNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(noticeMessage)
        }
        .task { await refreshReportedAndNotice() }
        .task {
            openPushedCard()
            if !sentCards.isEmpty { push.offerPermissionIfNeeded() }
        }
        .onChange(of: push.pendingCardID) { openPushedCard() }
        .onChange(of: showCreateFlow) {
            if !showCreateFlow && !sentCards.isEmpty { push.offerPermissionIfNeeded() }
        }
        .alert("Get notified about your cards?", isPresented: $push.showPrePrompt) {
            Button("Turn On") { Task { await push.requestPermission() } }
            Button("Not Now", role: .cancel) { push.declinePrePrompt() }
        } message: {
            Text("We can let you know when a card you sent is opened, or when someone replies to it or reacts to it. You can change this any time in Profile.")
        }
        .onChange(of: selectedTab) {
            if selectedTab == .sent { Task { await refreshReportedAndNotice() } }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await refreshReportedAndNotice() } }
        }
    }

    // MARK: - Notices

    // Complaint warnings / suspension notices written by the server. Shows the
    // newest unseen one (most recent is the most relevant) and marks all seen.
    // Cheap server checks (a few bytes each), run whenever this screen shows,
    // the Sent tab is selected, or the app returns to the foreground.
    private func refreshReportedAndNotice() async {
        if let id = authManager.currentUserID {
            await CardRestoreService.refreshReported(userID: id, draftManager: draftManager)
        }
        await showPendingNotice()
        await refreshLastActivity()
    }

    private func refreshLastActivity() async {
        let ids = draftManager.drafts.filter { $0.status == .sent }.compactMap(\.cardID)
        lastActivity = await CardReplyService.fetchLastActivity(for: ids)
    }

    private func showPendingNotice() async {
        let notices = await UserNoticeService.fetchUnseen()
        guard let latest = notices.last else { return }
        noticeTitle = latest.kind == "ban" ? "Account Suspended" : "Card Reported"
        noticeMessage = latest.message
        showNotice = true
        await UserNoticeService.markSeen(notices)
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
        resumeParams = ResumeParams(draft: draft, step: 4, draftID: snapshot.id, originalStatus: .sent)
    }

    // "Copy & Edit" from SentCardDetailSheet — same clone + save-as-new-draft
    // + resume-at-Style-It behavior as CreateFlowView's onEditCard for a sent card.
    private func copyAndEditCard(_ draft: PostcardDraft) {
        let clone = draft.cloneExact()
        let newID = draftManager.save(draft: clone, currentStep: 1, status: .unsent, existingID: nil)
        resumeParams = ResumeParams(draft: clone, step: 1, draftID: newID, originalStatus: .unsent)
    }

    // MARK: - Drafts

    /// A tapped push names a card: show its Sent Card sheet (if it is on this device).
    private func openPushedCard() {
        guard let id = push.pendingCardID else { return }
        push.pendingCardID = nil
        guard let snapshot = draftManager.drafts.first(where: { $0.cardID == id && $0.status == .sent }) else { return }
        selectedTab = .sent
        sentDetailSnapshot = snapshot
    }

    private var unsentDrafts: [PostcardDraftSnapshot] {
        draftManager.drafts.filter { $0.status == .unsent }.sorted { $0.lastModified > $1.lastModified }
    }
    private var sentCards: [PostcardDraftSnapshot] {
        draftManager.drafts
            .filter { $0.status == .sent && !draftManager.isHidden($0) }
            .sorted { sentOrderDate($0) > sentOrderDate($1) }
    }

    // Newest first by the greatest of: last modified/sent, last reaction, last reply.
    private func sentOrderDate(_ snapshot: PostcardDraftSnapshot) -> Date {
        max(snapshot.lastModified, snapshot.cardID.flatMap { lastActivity[$0] } ?? .distantPast)
    }

    private var ringsContent: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                VStack(spacing: 16) {
                    Text("Gather your people")
                        .font(.system(size: 32, weight: .bold))
                    // Paragraph gap is half a line (21pt text, ~25pt line).
                    VStack(spacing: 12) {
                        Text("Send invitations, thank you's,\nholiday cards, announcements.")
                        Text("By mail or digital.")
                        Text("Every moment, delivered.")
                    }
                    .font(.system(size: 21, weight: .semibold))
                    .multilineTextAlignment(.center)
                }
                .padding(.top, geo.size.height / 20)

                Text("Coming Spring 2027")
                    .font(.system(size: 21, weight: .semibold))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    // The Postcards/Profile bar is a .safeAreaInset on an
                    // ancestor of the NavigationStack, so it isn't reflected
                    // in this view's safe area — clear it by hand (~64pt bar
                    // + 32pt breathing room).
                    .padding(.bottom, 96)
            }
            .foregroundColor(.brandBlue)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
                            loadBackImage: { nil },
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
                            loadBackImage: { snapshot.cardID.flatMap { draftManager.loadBack(for: $0) } },
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
    // Drafts have no baked back yet (it's only rendered at send time), so the
    // Drafts grid passes `{ nil }` and the download saves just the front.
    let loadBackImage: () -> UIImage?
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var image: UIImage? = nil
    @State private var reactions: [CardReaction] = []
    @State private var replyCount: Int = 0
    @State private var openedAt: Date? = nil

    // One shared diameter for the trash, download, and reply/reaction circles.
    private let circleSize: CGFloat = 32

    // The gallery tile shows only the most recent reaction; the Sent Card sheet
    // lists them all. A missing date counts as oldest; ties go to the later row.
    private var latestReactionEmoji: String? {
        reactions.enumerated()
            .max { ($0.element.sent_at ?? .distantPast, $0.offset) < ($1.element.sent_at ?? .distantPast, $1.offset) }?
            .element.emoji
    }

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
                    .frame(width: circleSize, height: circleSize)
                    .background(Color.brandBlue)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, hasWhiteBorder ? 18 : 8)
            .padding(.bottom, hasWhiteBorder ? 16 : 8)
        }
        // Reaction/opened and reply summary — same corner-inset logic
        // as the trash button (mirrored to the opposite corner) so both clear
        // a baked-in "Classic" border the same way.
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 4) {
                if showsReplyBadges {
                    // One circle: the latest reaction if there is one, else the
                    // eyes once the card has been opened, else nothing.
                    if let emoji = latestReactionEmoji {
                        Text(emoji)
                            .font(.system(size: 16))
                            .frame(width: circleSize, height: circleSize)
                            .background(Color.brandBlue)
                            .clipShape(Circle())
                    } else if openedAt != nil {
                        Image(systemName: "binoculars.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: circleSize, height: circleSize)
                            .background(Color.brandBlue)
                            .clipShape(Circle())
                    }
                    if replyCount > 0 {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: circleSize, height: circleSize)
                            .background(Color.brandBlue)
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.trailing, hasWhiteBorder ? 18 : 8)
            .padding(.bottom, hasWhiteBorder ? 16 : 8)
        }
        .task(id: snapshot.lastModified) {
            image = loadImage()
            guard showsReplyBadges, let cardID = snapshot.cardID else { return }
            openedAt = await CardReplyService.fetchFirstOpened(for: cardID)
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
