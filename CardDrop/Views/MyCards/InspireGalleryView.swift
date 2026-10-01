import SwiftUI

/// The "Get Inspired" gallery — a masonry grid of curated real CardDrop
/// postcards (`marketing_cards.in_inspire = true`), same layout technique as
/// the Sent/Drafts grids (`MasonryLayout` in MyCardsView.swift). Tapping a
/// tile opens `InspireSwipeDeckView`, a full-screen autoplaying reveal deck
/// starting at that card.
struct InspireGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = InspireGalleryStore.shared
    @State private var startingIndex: GalleryStart?

    private struct GalleryStart: Identifiable {
        let id = UUID()
        let index: Int
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.cards.isEmpty && store.isLoadingInitial {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.cards.isEmpty {
                    ContentUnavailableView(
                        "Nothing Yet",
                        systemImage: "sparkles",
                        description: Text("Check back soon for real CardDrop postcards.")
                    )
                } else {
                    ScrollView {
                        MasonryLayout(columns: 2, columnSpacing: 12, lineSpacing: 12) {
                            ForEach(Array(store.cards.enumerated()), id: \.element.id) { index, card in
                                InspireCardTile(card: card)
                                    .onTapGesture { startingIndex = GalleryStart(index: index) }
                                    .task { await store.loadMoreIfNeeded(currentItem: card) }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 4)

                        if store.isLoadingMore {
                            ProgressView()
                                .padding(.vertical, 16)
                        }
                    }
                    .contentMargins(.bottom, 80, for: .scrollContent)
                    .refreshable { await store.loadInitial(forceRefresh: true) }
                }
            }
            .navigationTitle("Get Inspired")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem("Close", placement: .cancellationAction, style: .bare) { dismiss() }
            }
        }
        .task { await store.loadInitial() }
        .fullScreenCover(item: $startingIndex) { start in
            InspireSwipeDeckView(startIndex: start.index, onClose: { dismiss() })
        }
    }
}

/// A grid tile showing the finished thumbnail — exact same
/// natural-aspect-ratio masonry technique as CardTileView (Sent/Drafts):
/// portrait and landscape cards mixed together, each sized by its own real
/// aspect ratio, no forced square, no per-tile jitter/offset.
private struct InspireCardTile: View {
    let card: InspireCard

    private var placeholderAspectRatio: CGFloat { card.is_portrait ? 2.0 / 3.0 : 3.0 / 2.0 }

    var body: some View {
        AsyncImage(url: card.thumbnailURL) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(Color(.secondarySystemBackground))
                    .aspectRatio(placeholderAspectRatio, contentMode: .fit)
                    .overlay(phase.error == nil ? AnyView(ProgressView()) : AnyView(EmptyView()))
            }
        }
        .clipShape(Rectangle())
        .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Swipe deck

/// Full-screen autoplaying reveal deck, starting at `startIndex` into
/// `InspireGalleryStore.shared.cards`. Each card cycles raw → crossfade →
/// finished → advance on its own; swiping left/right jumps to the next/
/// previous card on demand (cancelling and restarting the cycle); press and
/// hold pauses wherever the current card's cycle is, release resumes it.
private struct InspireSwipeDeckView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = InspireGalleryStore.shared
    @State private var currentIndex: Int
    // A new card ALWAYS takes focus showing After (the finished front) —
    // Before is only ever reached by the user manually tapping the
    // Before/After toggle below the photo, never automatically.
    @State private var showingAfter = true
    // Starts paused — no autoplay. The user chooses manual (arrow)
    // navigation or taps resume to let it auto-advance through the
    // finished images on a timer (slideshow never auto-shows Before).
    @State private var isPaused = true
    // Bumped by the Before/After toggle to reset the current card's
    // auto-advance timer — see the combined task id below.
    @State private var replayCount = 0
    // The raw "before" photo's aspect ratio is unknown ahead of time (unlike
    // the finished front, always exactly 2:3 or 3:2) — loaded as a real
    // UIImage (not AsyncImage) so its true pixel size is available for the
    // fitted-size math below, needed to position the label right above it.
    @State private var rawUIImage: UIImage?
    @State private var beforeLabelHeight: CGFloat = 24
    // Measured once the control pill lays out — used to position it
    // directly below the photo, mirroring how the label sits directly above it.
    @State private var controlsHeight: CGFloat = 60
    // Called (in addition to this view's own dismiss()) when Close is
    // tapped, so closing the deck also closes the grid behind it — the
    // user shouldn't land back on the grid after leaving the deck.
    let onClose: () -> Void

    // Matches SampleCardCarousel's transitionDuration — same soothing pace.
    private static let crossfadeDuration = 2.0
    private static let finishedHold: UInt64 = 6_000_000_000

    init(startIndex: Int, onClose: @escaping () -> Void) {
        _currentIndex = State(initialValue: startIndex)
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            if store.cards.indices.contains(currentIndex) {
                cardView(for: store.cards[currentIndex])
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.width < -60 {
                        advance(by: 1)
                    } else if value.translation.width > 60 {
                        advance(by: -1)
                    }
                }
        )
        .overlay(alignment: .topLeading) {
            // No NavigationStack/toolbar here (this is a plain
            // fullScreenCover), so this replicates ToolbarPillButton's
            // .bare style by hand — same look as the Close control on
            // SentCardDetailSheet and the Inspire gallery's own toolbar.
            Button(action: {
                dismiss()
                onClose()
            }) {
                Text("Close")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.brandBlue)
            }
            .padding()
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 32) {
                Button(action: { advance(by: -1) }) {
                    Image(systemName: "arrow.left")
                }
                Button(action: { isPaused.toggle() }) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                }
                Button(action: { advance(by: 1) }) {
                    Image(systemName: "arrow.right")
                }
            }
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(Color.brandBlue)
            .clipShape(Capsule())
            .padding(.bottom, 32)
        }
        .task(id: "\(currentIndex)-\(replayCount)") { await runCycle() }
        .task(id: currentIndex) {
            if store.cards.indices.contains(currentIndex) {
                await store.loadMoreIfNeeded(currentItem: store.cards[currentIndex])
            }
        }
        .task(id: currentIndex) {
            // Deliberately doesn't clear rawUIImage first — keeps showing
            // the previous card's raw photo (briefly, harmlessly) instead
            // of flashing blank while the new one fetches. Most noticeable
            // the first time a card's raw photo is fetched this session
            // (e.g. right after wrapping around to a card not visited yet).
            if store.cards.indices.contains(currentIndex) {
                await loadRawImage(from: store.cards[currentIndex].beforeURL)
            }
        }
    }

    /// The photo's true fitted size within a `maxW`x`maxH` box, preserving
    /// its own aspect ratio (long side reaches the box edge) — computed
    /// analytically, not measured from a laid-out view (which would only
    /// ever report the box size, not the letterboxed content inside it).
    private func fittedSize(aspect: CGFloat, maxW: CGFloat, maxH: CGFloat) -> CGSize {
        guard maxW > 0, maxH > 0, aspect > 0 else { return .zero }
        let boxAspect = maxW / maxH
        if aspect > boxAspect {
            return CGSize(width: maxW, height: maxW / aspect)
        } else {
            return CGSize(width: maxH * aspect, height: maxH)
        }
    }

    private func loadRawImage(from url: URL) async {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return }
        rawUIImage = image
    }

    private func cardView(for card: InspireCard) -> some View {
        GeometryReader { geo in
            let maxW = geo.size.width - 32
            let maxH = geo.size.height * 0.6

            let rawAspect = rawUIImage.map { $0.size.width / $0.size.height } ?? 1
            let rawSize = fittedSize(aspect: rawAspect, maxW: maxW, maxH: maxH)

            let frontAspect: CGFloat = card.is_portrait ? 2.0 / 3.0 : 3.0 / 2.0
            let frontSize = fittedSize(aspect: frontAspect, maxW: maxW, maxH: maxH)

            let activeSize = showingAfter ? frontSize : rawSize
            // No label at all above the finished postcard — it speaks for
            // itself — so no space needs to be reserved in that state.
            let activeLabelHeight = showingAfter ? 0 : beforeLabelHeight
            let centerX = geo.size.width / 2
            let centerY = geo.size.height / 2

            ZStack {
                // Photo — dead center of the full viewport, always.
                ZStack {
                    if let rawUIImage {
                        Image(uiImage: rawUIImage)
                            .resizable()
                            .frame(width: rawSize.width, height: rawSize.height)
                    }
                }
                .opacity(showingAfter ? 0 : 1)
                // Tapping the Original photo itself does the same thing as
                // "Show Postcard" — deliberately one-directional: tapping
                // the postcard does NOT switch to Original, only the
                // control below does that, so admiring/swiping the
                // postcard (the primary content) never accidentally toggles.
                .contentShape(Rectangle())
                .onTapGesture { if !showingAfter { toggleBeforeAfter() } }
                .allowsHitTesting(!showingAfter)
                .position(x: centerX, y: centerY)

                AsyncImage(url: card.frontURL) { phase in
                    if let image = phase.image {
                        image.resizable()
                            .frame(width: frontSize.width, height: frontSize.height)
                    }
                }
                .opacity(showingAfter ? 1 : 0)
                .position(x: centerX, y: centerY)

                // Label — pinned directly above whichever photo is
                // currently showing, using ITS actual fitted height, so it
                // hugs the photo's real top edge regardless of orientation.
                ZStack {
                    // Only ever shown in the Original state — the finished
                    // postcard gets no label at all, it speaks for itself.
                    Text("Original Photo")
                        .font(.headline)
                        .fontWeight(.regular)
                        .foregroundColor(.black)
                        .opacity(showingAfter ? 0 : 1)
                        .background(
                            GeometryReader { g in
                                Color.clear.onAppear { beforeLabelHeight = g.size.height }
                            }
                        )
                }
                .position(x: centerX, y: centerY - activeSize.height / 2 - activeLabelHeight / 2 - 12)

                // Manual Before/After toggle — the ONLY way Before is ever
                // shown. Label reads as the action (what tapping switches
                // TO). Also resets the current card's auto-advance timer
                // (bumping replayCount restarts runCycle() fresh) so a
                // running slideshow doesn't advance mid-look.
                Button(action: toggleBeforeAfter) {
                    Text(showingAfter ? "Show Original" : "Show Postcard")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.brandBlue)
                }
                .background(
                    GeometryReader { g in
                        Color.clear.onAppear { controlsHeight = g.size.height }
                    }
                )
                .position(x: centerX, y: centerY + activeSize.height / 2 + controlsHeight / 2 + 12)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// Waits out this card's dwell time, then — only if playing — advances
    /// to the next card. Never touches `showingAfter`: Before is reached
    /// ONLY by the user tapping the Before/After toggle, never
    /// automatically. Cancelled and restarted fresh (resetting the dwell
    /// timer) by the combined task id below, whenever the card changes OR
    /// the user toggles Before/After.
    private func runCycle() async {
        try? await Task.sleep(nanoseconds: Self.finishedHold)
        guard !Task.isCancelled else { return }

        while isPaused {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if Task.isCancelled { return }
        }
        advance(by: 1)
    }

    /// Shared by the Before/After toggle button and tapping the Original
    /// photo directly — same action either way.
    private func toggleBeforeAfter() {
        withAnimation(.easeInOut(duration: Self.crossfadeDuration)) { showingAfter.toggle() }
        replayCount += 1
    }

    /// Wraps around in both directions — reaching the end loops back to the
    /// first card, and going back past the first loops to the last. Always
    /// forces the new card to show After — Before never carries over from
    /// whatever the previous card was showing.
    private func advance(by delta: Int) {
        guard !store.cards.isEmpty else { return }
        withAnimation(.easeInOut(duration: Self.crossfadeDuration)) {
            currentIndex = (currentIndex + delta + store.cards.count) % store.cards.count
            showingAfter = true
        }
    }
}
