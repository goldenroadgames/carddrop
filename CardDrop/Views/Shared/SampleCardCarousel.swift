import SwiftUI

// A loose "pile" of sample postcards for the landing page — every card sits
// in roughly the same spot, each at its own small fixed tilt/offset so the
// stack reads as a messy pile rather than perfectly aligned photos. Only the
// top two are EVER rendered, and the back card is only ever visible DURING a
// crossfade — at rest, only the front card is on screen at all (back sits at
// opacity 0, fully absent). When it's time to advance, front and back fade
// simultaneously — front 1 -> 0, back 0 -> 1, same duration, perfectly
// synchronized — then the old back (now at full opacity) becomes the new
// resting front with zero visual change, and the next card behind it starts
// back at 0 (absent) until the cycle repeats. No lateral sliding, no big
// rotation, no more than one crossfade happening at once — a previous
// fanned/sliding "ring" version (see git history) proved genuinely
// nauseating (real user report, not just a preference) since rotating
// several cards at once is a classic vestibular trigger; a plain synchronized
// crossfade has none of that.
//
// Images are a mix of portrait and landscape cards, so each card's own frame
// hugs its real aspect ratio (measured once its image loads) rather than
// every card sharing one fixed landscape box.
//
// Images come from two sources, additively:
// - `stockImageNames`: a couple of images bundled in Assets.xcassets,
//   rendered synchronously (no network, no loading state) so the pile is
//   never empty/placeholder-only on first appear, however slow or flaky the
//   network is.
// - `imageNames`: the public "carousel_postcards" Supabase Storage bucket
//   (not bundled, so the same sample set can be reused by the web landing
//   page later without duplicating files per platform) — these load
//   asynchronously and are appended once fetched. Public URL is hand-built
//   the same way CardUploadService does for the "card-images" bucket — this
//   codebase doesn't use the SDK's getPublicURL() anywhere, so this matches
//   the established convention.
enum CardImageSource: Hashable {
    case stock(String)   // Assets.xcassets image name
    case remote(String)  // object path within the "carousel_postcards" bucket
}

struct SampleCardCarousel: View {
    var stockImageNames: [String] = []
    var imageNames: [String] = []   // object paths within the "carousel_postcards" bucket, e.g. "sample_1.jpg"
    var cardHeight: CGFloat = 200
    var portraitAspectRatio: CGFloat = 4.0 / 6.0   // width : height
    var landscapeAspectRatio: CGFloat = 6.0 / 4.0  // width : height
    var cardCornerRadius: CGFloat = 0   // hard square corners, matching the actual card images
    var secondsPerCard: Double = 8.0            // total time a card spends resting on top, INCLUDING its own crossfade — so restDuration = secondsPerCard - transitionDuration
    var transitionDuration: Double = 2.0        // duration of the crossfade — front fades out while back fades in, fully synchronized
    var pauseAtStockOneDuration: Double = 2.0   // EXTRA rest time (on top of the normal per-card rest) while stock #1 (index 0) is on top
    var maxTiltDegrees: Double = 6              // each card's own small fixed tilt, for the "messy pile" look — deliberately small: no card ever animates its rotation, this is just a static per-card offset
    var maxPileOffset: CGFloat = 6              // each card's own small fixed x/y offset, same reasoning as maxTiltDegrees
    var maxCardWidth: CGFloat = .infinity        // the actual device screen width — no single card can render wider than this

    // Single synchronized crossfade per cycle — nothing ever snaps
    // instantly, and the two cards are ONLY ever both visible during this
    // one animation:
    //   Rest: frontOpacity = 1, backOpacity = 0 (back fully absent).
    //   Crossfade: frontOpacity 1 -> 0 while backOpacity 0 -> 1, together,
    //   over transitionDuration.
    //   After: currentIndex advances — the old back (already at opacity 1)
    //   becomes the new front with ZERO visual change (same value, same
    //   pixels, just relabeled), and backOpacity resets to 0 for the next
    //   card in line, which stays invisible until the next crossfade begins.
    @State private var frontOpacity: Double = 1.0
    @State private var backOpacity: Double = 0.0
    @State private var currentIndex: Int = 0
    // Each card's actual rendered width, keyed by image name, measured once
    // its image loads and sizes itself to its own native aspect ratio.
    @State private var measuredWidths: [String: CGFloat] = [:]

    // Used for sizing the pile's own frame only (not any individual card's
    // frame) — the midpoint between a typical portrait and landscape card's
    // width.
    private var referenceWidth: CGFloat {
        cardHeight * (portraitAspectRatio + landscapeAspectRatio) / 2
    }

    // Stock images first, bucket images appended once loaded — stock alone
    // is always enough to fill the pile, so there's never an empty/
    // placeholder-only moment while the bucket fetch is in flight.
    private var sources: [CardImageSource] {
        stockImageNames.map { .stock($0) } + imageNames.map { .remote($0) }
    }

    private var nextIndex: Int {
        let count = sources.count
        guard count > 0 else { return 0 }
        return (currentIndex + 1) % count
    }

    var body: some View {
        ZStack {
            if !sources.isEmpty {
                // Back card first (painter's order) — see the comment above
                // the @State declarations for exactly when this is visible
                // vs. fully absent.
                cardView(sources[nextIndex])
                    .rotationEffect(.degrees(tiltAngle(for: nextIndex)))
                    .offset(pileOffset(for: nextIndex))
                    .opacity(backOpacity)

                cardView(sources[currentIndex])
                    .rotationEffect(.degrees(tiltAngle(for: currentIndex)))
                    .offset(pileOffset(for: currentIndex))
                    .opacity(frontOpacity)
            }
        }
        .frame(width: referenceWidth + maxPileOffset * 2 + 24, height: cardHeight + maxPileOffset * 2 + 24)
        // A rotated card's corner can poke past this frame's un-rotated
        // bounds — without clipping, that exposes whatever sits behind the
        // pile (the wordmark mosaic background) right through the gap, the
        // same "ghost edge" bug as the old ring carousel's aspect-ratio
        // mismatch, just a different cause. Always keep this.
        .clipped()
        .task { await runPileLoop() }
    }

    // Deterministic per-index tilt/offset — the SAME card always sits the
    // same way in the pile rather than re-randomizing every cycle, which
    // would look jittery. Not meant to be statistically random, just varied
    // enough that consecutive cards don't look identical. Sign strictly
    // alternates by index parity so consecutive cards visibly lean opposite
    // ways (rather than a same-signed run looking like a lopsided stack);
    // magnitude still varies (40%-100% of maxTiltDegrees) so it's not
    // perfectly rhythmic.
    private func tiltAngle(for index: Int) -> Double {
        let raw = Double((index * 47) % 23) / 22.0   // 0...1
        let magnitude = maxTiltDegrees * (0.4 + 0.6 * raw)
        let sign: Double = index % 2 == 0 ? 1 : -1
        return sign * magnitude
    }

    private func pileOffset(for index: Int) -> CGSize {
        let rawX = Double((index * 31) % 13) / 12.0  // 0...1
        let rawY = Double((index * 19) % 11) / 10.0  // 0...1
        return CGSize(width: (rawX * 2 - 1) * maxPileOffset, height: (rawY * 2 - 1) * maxPileOffset)
    }

    // Rest duration for whichever card is currently on top — the normal
    // per-card rest, plus pauseAtStockOneDuration extra when that card is
    // stock #1 (always sources[0], since stockImageNames comes first).
    private func restDuration(forIndexOnTop index: Int) -> Double {
        let base = max(0, secondsPerCard - transitionDuration)
        return index == 0 ? base + pauseAtStockOneDuration : base
    }

    // Rest with only the front visible, then crossfade front->0/back->1
    // together, then swap: the old back (already at full opacity) becomes
    // the new front with zero visual change, and the next card resets to
    // invisible behind it. Loops forever; cancelled automatically when the
    // view disappears (`.task`).
    private func runPileLoop() async {
        while !Task.isCancelled {
            let count = sources.count
            guard count > 0 else {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            let rest = restDuration(forIndexOnTop: currentIndex)
            try? await Task.sleep(nanoseconds: UInt64(max(0, rest) * 1_000_000_000))
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: transitionDuration)) {
                frontOpacity = 0
                backOpacity = 1
            }
            try? await Task.sleep(nanoseconds: UInt64(max(0, transitionDuration) * 1_000_000_000))
            guard !Task.isCancelled else { return }

            // Swap: old back (currently at opacity 1) becomes the new front
            // — frontOpacity is set to the SAME value it already ended the
            // crossfade at, so this is visually a no-op. backOpacity resets
            // to 0 for the next card in line — also a no-op, since that
            // slot's underlying source just changed to one that's never
            // been shown yet, and 0 opacity means there's nothing to see
            // regardless.
            currentIndex = (currentIndex + 1) % count
            frontOpacity = 1
            backOpacity = 0
        }
    }

    private func imageURL(for name: String) -> URL {
        SupabaseConfig.projectURL.appendingPathComponent("storage/v1/object/public/carousel_postcards/\(name)")
    }

    // Prefixed so a stock and a remote image that happen to share a name
    // don't collide in measuredWidths.
    private func widthKey(for source: CardImageSource) -> String {
        switch source {
        case .stock(let name): return "stock:\(name)"
        case .remote(let name): return "remote:\(name)"
        }
    }

    @ViewBuilder
    private func cardView(_ source: CardImageSource) -> some View {
        let key = widthKey(for: source)
        // Capped at the PILE's own available width (referenceWidth), not
        // just maxCardWidth (the full device width) — otherwise a landscape
        // card (wider than referenceWidth) renders wider than the pile's
        // own frame and gets physically cropped by that frame's `.clipped()`
        // (needed to stop rotated corners exposing the background — see
        // that modifier's own comment). Height scales down proportionally
        // to preserve aspect ratio when the cap kicks in, same technique as
        // the web ring carousel's earlier "ghost edge" fix.
        let measuredWidth = measuredWidths[key] ?? referenceWidth
        let cap = min(maxCardWidth, referenceWidth)
        let width = min(measuredWidth, cap)
        let height = measuredWidth > cap ? cardHeight * (cap / measuredWidth) : cardHeight

        switch source {
        case .stock(let name):
            // Bundled in Assets.xcassets — renders synchronously, no
            // loading/failure state, so these are always on screen
            // immediately regardless of network conditions.
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: cardHeight)
                .background(
                    GeometryReader { g in
                        Color.clear.onAppear { measuredWidths[key] = g.size.width }
                    }
                )
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

        case .remote(let name):
            AsyncImage(url: imageURL(for: name)) { phase in
                switch phase {
                case .success(let image):
                    // Identical chain to the .stock branch above — same
                    // modifiers, same order, applied directly to the image
                    // itself (not to AsyncImage as a wrapping container),
                    // so a bucket photo is sized exactly the same way a
                    // bundled one is, no divergent layout behavior between
                    // the two sources.
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: cardHeight)
                        .background(
                            GeometryReader { g in
                                Color.clear.onAppear { measuredWidths[key] = g.size.width }
                            }
                        )
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                default:
                    // Covers both the loading and failure cases — keeps the
                    // pile visually complete instead of rendering a blank
                    // gap (the stock images already guarantee the pile isn't
                    // empty, this just covers a slow/failed bucket fetch for
                    // this particular slot).
                    RoundedRectangle(cornerRadius: cardCornerRadius)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: width, height: height)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 28))
                                .foregroundColor(.gray.opacity(0.5))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                }
            }
        }
    }
}

#Preview {
    SampleCardCarousel(imageNames: ["sample_1.jpg", "sample_2.jpg", "sample_3.jpg", "sample_4.jpg"])
        .padding(.vertical, 60)
}
