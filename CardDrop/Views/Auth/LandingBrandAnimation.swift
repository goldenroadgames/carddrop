import SwiftUI

// Landing-page reveal, in two layers:
//
// 1. A FLOATING wordmark ("Card"+"Drop" only) — a standalone overlay used
//    purely for the opening beat: "Card" starts centered in the viewport,
//    "Drop" falls from off-screen and docks onto it, then the formed
//    wordmark keeps falling to the bottom of the viewport and bounces.
// 2. The REAL content — one single VStack containing the wordmark+tagline
//    block, the carousel, the description, AND the sign-in controls (passed
//    in as `controls`, a real 4th element of this same stack, not a
//    separate overlay) — sits parked entirely below the viewport the whole
//    time step 1 is playing, guaranteeing nothing can peek into view no
//    matter how tall it is, since none of it is anywhere near the fold yet.
//
// At the bounce, the floating layer disappears and the real stack — already
// parked exactly where the floating wordmark ended up — takes over: being
// one physical VStack, a single shared offset naturally rises the wordmark,
// carousel, description, AND the sign-in controls together, in lockstep.
// That shared offset stops at 0 (home) — the controls arrive there and stay,
// since nothing further ever touches them. Only the wordmark+carousel+
// description sub-group keeps going, via its own separate offset layered on
// top, overshooting a bit past its final spot before floating back down.
//
// Final order (top to bottom): wordmark+tagline, carousel, description,
// sign-in controls — the carousel fills exactly whatever space is left
// between the wordmark block and the description, computed from each
// element's own intrinsic height (not from on-screen position, to avoid a
// circular layout dependency).
//
// PORTABILITY NOTE: this same reveal is planned for the web app's landing
// page too (a separate, non-Swift codebase), so every timing/position value
// below is a named constant rather than an inline magic number — treat this
// struct's `Timing`/`Layout` values as the source-of-truth spec to port,
// not just as SwiftUI-specific tuning.
// Nested types with static stored properties aren't allowed inside a
// generic type in Swift, so these live at file scope instead of nested
// inside LandingBrandAnimation<Controls>.
private enum LandingTiming {
    static let initialPause: TimeInterval = 0.15        // beat before "Drop" starts falling
    static let dropFallDuration: TimeInterval = 0.71    // "Drop" falling into place
    static let wordmarkFallDuration: TimeInterval = 0.79 // formed wordmark falling to the bottom of the viewport
    static let thudSquashDuration: TimeInterval = 0.08  // impact squash (down), at the bottom bounce
    static let riseDuration: TimeInterval = 2.0         // shared rise from the bottom bounce up to the final resting spot
    static let overshootDuration: TimeInterval = 0.2    // content sub-group rising past its final spot (controls have already stopped)
    static let settleDuration: TimeInterval = 0.5       // content sub-group spring-settling back down onto its final spot
    static let backdropFadeDuration: TimeInterval = 0.4 // gray backdrop fading away once everything has settled home
}

// A single continuously-animated value drives BOTH "Drop" falling onto
// "Card" AND the formed wordmark's subsequent fall to the bottom, so there
// is exactly one animation curve across the whole motion — no restart, no
// dead-stop-then-reaccelerate stutter at the dock point.
//
// `fallValue` is "Drop's absolute Y minus the viewport center" (the same
// quantity the old `dropOffsetY` represented pre-dock). From it:
//   rowY           = center + max(0, fallValue - attachOffset)   // Card's Y
//   dropOffsetY    = min(fallValue, attachOffset)                // Drop's Y relative to Card
// Before docking, fallValue < attachOffset, so rowY stays pinned at center
// while Drop closes the gap. Once fallValue passes attachOffset, rowY
// starts rising 1:1 with fallValue while the relative offset clamps at
// attachOffset — i.e. Drop is "caught" and the whole assembly keeps falling
// together, with the transition itself being perfectly smooth because it's
// the same underlying value the whole time.
private struct FallingWordmark: View, Animatable {
    var fallValue: CGFloat
    let center: CGFloat
    let attachOffset: CGFloat
    let font: Font
    var scale: CGFloat
    var opacityValue: Double
    let xCenter: CGFloat

    var animatableData: CGFloat {
        get { fallValue }
        set { fallValue = newValue }
    }

    var body: some View {
        let rowY = center + max(0, fallValue - attachOffset)
        let dropRelativeY = min(fallValue, attachOffset)
        HStack(alignment: .top, spacing: 0) {
            Text("Card")
                .font(font)
                .foregroundColor(.brandBlue)
            Text("Drop")
                .font(font)
                .foregroundColor(.brandBlue)
                .offset(y: dropRelativeY)
        }
        .scaleEffect(scale)
        .opacity(opacityValue)
        .position(x: xCenter, y: rowY)
    }
}

private enum LandingLayout {
    static let dropStartMargin: CGFloat = 40            // extra clearance above the top edge, on top of whatever's needed to fully clear it
    static let dropAttachOffset: CGFloat = 8            // "Drop"'s final offset once docked (matches CardDropWordmark's default)
    static let overshootDistance: CGFloat = 30          // how far past its final resting spot the content sub-group rises before floating back down
    static let thudSquashScale: CGFloat = 0.92
    static let wordmarkFontSize: CGFloat = 38           // 34 * 1.5 * 0.75
    static let taglineBaseFontSize: CGFloat = 60        // deliberately oversized — minimumScaleFactor shrinks it to exactly match the wordmark's width
}

struct LandingBrandAnimation<Controls: View>: View {
    var description: String
    var stockImageNames: [String]   // bundled Assets.xcassets names — always available, no network
    var sampleImageNames: [String]  // Supabase "carousel_postcards" bucket names — additive, once fetched
    var pillHeight: CGFloat   // top padding, and the gap above the sign-in controls, = 1x/0.75x this
    let controls: Controls

    init(
        description: String,
        stockImageNames: [String],
        sampleImageNames: [String],
        pillHeight: CGFloat,
        @ViewBuilder controls: () -> Controls
    ) {
        self.description = description
        self.stockImageNames = stockImageNames
        self.sampleImageNames = sampleImageNames
        self.pillHeight = pillHeight
        self.controls = controls()
    }

    private typealias Timing = LandingTiming
    private typealias Layout = LandingLayout

    // MARK: Floating layer (opening beat only)
    // Real starting value (dynamic, based on viewport height) is set in
    // applyInitialPositions(); this default only matters before that runs.
    // See FallingWordmark: this single value drives both "Drop" catching up
    // to "Card" AND the pair's subsequent fall, as one continuous motion.
    @State private var dropFallValue: CGFloat = -1000
    @State private var floatingScale: CGFloat = 1.0  // thud squash
    @State private var floatingOpacity: Double = 1

    // MARK: Real content
    // Shared rigid-body offset applied to the WHOLE outer stack (wordmark+
    // carousel+description sub-group, AND the sign-in controls) — since
    // they're one physical VStack, this single offset is all it takes to
    // keep them moving in lockstep. Starts parked below the viewport
    // (wherever the floating wordmark will end up) and rises to 0 (home) at
    // the handoff, then is never touched again — which is exactly why the
    // controls simply stop there.
    @State private var groupOffsetY: CGFloat = 0
    // Extra offset applied ONLY to the wordmark+carousel+description
    // sub-group, layered on top of groupOffsetY, after groupOffsetY has
    // already reached 0 — the overshoot-past-final-spot-then-float-back-down
    // that the sign-in controls don't participate in.
    @State private var stackOvershootY: CGFloat = 0
    @State private var wordmarkWidth: CGFloat = 200      // measured from the real "Card"+"Drop" layout once on appear
    @State private var cardRowNaturalY: CGFloat = 0      // measured; the real row's true resting Y (captured on the first frame, before any offset is applied)
    @State private var cardRowHeight: CGFloat = 0        // measured; the real row's own intrinsic height (also used for the floating copy, same font)
    @State private var descriptionHeight: CGFloat = 0    // measured; the description block's own intrinsic height
    @State private var wordmarkBlockHeight: CGFloat = 0  // measured; the wordmark+tagline block's own intrinsic height (independent of where it sits)
    @State private var controlsHeight: CGFloat = 0       // measured; the sign-in controls' own intrinsic height
    // The gray backdrop lives outside the clipped/geo-bound content so
    // `.ignoresSafeArea()` can actually extend it into the bottom safe
    // area; this opacity fades it away once the reveal fully settles, so
    // it doesn't linger as a permanent gray strip behind the final UI.
    @State private var backdropOpacity: Double = 1

    private var wordmarkFont: Font {
        Font(UIFont(name: "Inter-ExtraBold", size: Layout.wordmarkFontSize) ?? UIFont.boldSystemFont(ofSize: Layout.wordmarkFontSize))
    }

    var body: some View {
        GeometryReader { geo in
            // Whatever's left between the wordmark block and the
            // description, after the top padding, both their own intrinsic
            // heights, the gap above the controls, and the controls'
            // own height — the carousel is sized to fill exactly this,
            // clamped to 0 so a not-yet-measured first frame can't go
            // negative.
            let carouselHeight = max(
                0,
                (geo.size.height
                    - (pillHeight * 0.75)
                    - descriptionHeight
                    - wordmarkBlockHeight
                    - (pillHeight * 0.75)
                    - controlsHeight) * 1.0
            )

            // "Card"'s own starting position (before Drop docks) — the
            // mosaic's anchor tile is placed exactly here, so the real
            // "Card" sits precisely on top of a matching faint copy.
            let openingAnchor = CGPoint(
                x: geo.size.width / 2 - wordmarkWidth / 2,
                y: geo.size.height / 2 - cardRowHeight / 2
            )

            ZStack {
                // Stays visible (through the fall/bounce) until the real
                // content stack's opaque background rises up and covers it.
                CardDropMosaicBackground(
                    viewportSize: geo.size,
                    anchor: openingAnchor,
                    tileSize: CGSize(width: wordmarkWidth, height: cardRowHeight),
                    tileFont: wordmarkFont
                )

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: pillHeight * 0.75)

                    // Sub-group that gets the extra post-home overshoot —
                    // the sign-in controls below are NOT part of this.
                    VStack(spacing: 0) {
                        VStack(spacing: 8) {
                            HStack(alignment: .top, spacing: 0) {
                                Text("Card")
                                    .font(wordmarkFont)
                                    .foregroundColor(.brandBlue)
                                Text("Drop")
                                    .font(wordmarkFont)
                                    .foregroundColor(.brandBlue)
                                    .offset(y: Layout.dropAttachOffset)
                            }
                            .background(
                                GeometryReader { g in
                                    Color.clear.onAppear {
                                        cardRowNaturalY = g.frame(in: .named("landing")).minY
                                        cardRowHeight = g.size.height
                                        wordmarkWidth = g.size.width
                                    }
                                }
                            )

                            Text("On. The. FRIDGE.")
                                .font(.system(size: Layout.taglineBaseFontSize, weight: .bold))
                                .foregroundColor(.brandBlue)
                                .lineLimit(1)
                                .minimumScaleFactor(0.01)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: wordmarkWidth)
                        }
                        .background(
                            GeometryReader { g in
                                Color.clear.onAppear { wordmarkBlockHeight = g.size.height }
                            }
                        )

                        SampleCardCarousel(stockImageNames: stockImageNames, imageNames: sampleImageNames, cardHeight: carouselHeight / 1.2, maxCardWidth: geo.size.width)

                        Text(description)
                            .font(.callout.weight(.semibold))
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 32)
                            .background(
                                GeometryReader { g in
                                    Color.clear.onAppear {
                                        descriptionHeight = g.size.height
                                    }
                                }
                            )
                    }
                    .offset(y: stackOvershootY)

                    Spacer()
                        .frame(height: pillHeight * 0.75)

                    controls
                        .background(
                            GeometryReader { g in
                                Color.clear.onAppear { controlsHeight = g.size.height }
                            }
                        )
                }
                .frame(width: geo.size.width)
                // Opaque, and — by construction of the carouselHeight
                // formula above — naturally as tall as the viewport itself,
                // so this acts as a curtain: it rises in lockstep with the
                // content (same offset) and progressively covers the
                // mosaic background from below as it goes, until the
                // mosaic is fully hidden once everything settles at home.
                .background(Color(uiColor: .systemBackground))
                .offset(y: groupOffsetY)
                .coordinateSpace(name: "landing")

                // Floating wordmark — the opening beat. Sits on top of (and
                // independent from) the real content above.
                FallingWordmark(
                    fallValue: dropFallValue,
                    center: geo.size.height / 2,
                    attachOffset: Layout.dropAttachOffset,
                    font: wordmarkFont,
                    scale: floatingScale,
                    opacityValue: floatingOpacity,
                    xCenter: geo.size.width / 2
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .onAppear {
                // The stock images (Assets.xcassets) guarantee the carousel
                // is never empty, so the sequence starts immediately — no
                // need to wait on the Supabase bucket fetch.
                applyInitialPositions(viewportHeight: geo.size.height)
                runSequence(viewportHeight: geo.size.height)
            }
        }
        // Outside the clipped/geo-bound content above, so ignoresSafeArea
        // actually reaches the bottom edge instead of being cut off by that
        // inner .clipped(). Very subtle, purely so the rising white curtain
        // reads as a clear edge/boundary sweeping up, rather than the
        // reveal depending entirely on the faint mosaic tiles for contrast.
        // Fades away once the reveal fully settles, so it never lingers
        // behind the final UI.
        .background(
            Color(white: 0.97)
                .opacity(backdropOpacity)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func applyInitialPositions(viewportHeight: CGFloat) {
        // "Drop" starts fully above the top edge — computed from "Card"'s
        // own centered starting position (not a fixed constant), so it
        // clears the top on any screen size instead of only on the one it
        // happened to be tuned against. Expressed relative to viewport
        // center, per FallingWordmark's fallValue convention — this also
        // implicitly keeps "Card" centered (rowY = center) until fallValue
        // passes attachOffset.
        dropFallValue = -(viewportHeight / 2) - cardRowHeight - Layout.dropStartMargin
        // The real stack (including its own curtain background, which
        // starts at the VStack's very top — above the row, past the top
        // spacer) is parked with ITS top just past the bottom edge, not
        // just the row's — otherwise the curtain's leading edge (a strip as
        // tall as that top spacer) would still peek into view.
        groupOffsetY = viewportHeight
    }

    private func runSequence(viewportHeight: CGFloat) {
        // The formed wordmark falls all the way off the bottom of the
        // viewport — its row's top clears the bottom edge entirely.
        let floatingBottomY = viewportHeight + cardRowHeight / 2
        // Drop catching up to Card, and the pair's subsequent fall to the
        // bottom, are ONE continuous animation on fallValue — see
        // FallingWordmark. This is what eliminates the old catch-then-pause
        // stutter: there's only a single curve, never a second animation
        // restarting from zero velocity partway through.
        let combinedFallDuration = Timing.dropFallDuration + Timing.wordmarkFallDuration
        let finalFallValue = floatingBottomY - viewportHeight / 2 + Layout.dropAttachOffset

        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.initialPause) {
            withAnimation(.easeIn(duration: combinedFallDuration)) {
                dropFallValue = finalFallValue
            }
        }

        let thudStart = Timing.initialPause + combinedFallDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + thudStart) {
            withAnimation(.easeIn(duration: Timing.thudSquashDuration)) {
                floatingScale = Layout.thudSquashScale
            }
        }

        // Handoff: the floating wordmark disappears and the real stack
        // takes over, rising as one rigid body — since the content
        // sub-group and the sign-in controls are one physical VStack, this
        // single shared offset carries both up in lockstep.
        let riseStart = thudStart + Timing.thudSquashDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + riseStart) {
            withAnimation(.easeOut(duration: Timing.thudSquashDuration)) {
                floatingOpacity = 0
            }
            withAnimation(.linear(duration: Timing.riseDuration)) {
                groupOffsetY = 0
            }
        }

        // The sign-in controls are home now and stop — groupOffsetY is
        // never touched again. The content sub-group keeps going on its
        // own — overshooting a bit past its final spot, then floating back
        // down to settle.
        let overshootStart = riseStart + Timing.riseDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + overshootStart) {
            withAnimation(.easeOut(duration: Timing.overshootDuration)) {
                stackOvershootY = -Layout.overshootDistance
            }
        }

        let settleStart = overshootStart + Timing.overshootDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + settleStart) {
            withAnimation(.spring(response: Timing.settleDuration, dampingFraction: 0.6)) {
                stackOvershootY = 0
            }
        }

        // Everything is fully in place now — fade the gray backdrop away so
        // it doesn't linger behind the real, final landing page.
        let backdropFadeStart = settleStart + Timing.settleDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + backdropFadeStart) {
            withAnimation(.easeOut(duration: Timing.backdropFadeDuration)) {
                backdropOpacity = 0
            }
        }
    }
}

#Preview {
    LandingBrandAnimation(
        description: "Free digital postcards in seconds\nPrint and mail to make it real",
        stockImageNames: [],
        sampleImageNames: ["sample_postcard_1", "sample_postcard_2", "sample_postcard_3", "sample_postcard_4"],
        pillHeight: 54
    ) {
        Text("Sign-in controls")
    }
}
