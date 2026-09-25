import SwiftUI

// Continuous "ring" carousel for the landing page — every sample postcard
// is always on screen, arranged in a fanned stack around a centered front
// card, each one rotated and overlapped with its neighbor. The whole ring
// slides forward continuously (driven by elapsed time, not a discrete
// index), so cards smoothly rotate through the center slot rather than
// snapping between fixed positions.
//
// Images are a mix of portrait and landscape cards, so each card's own
// frame hugs its real aspect ratio (measured once its image loads) instead
// of every card sharing one fixed landscape box — a portrait image in a
// fixed landscape box would letterbox with empty padding on the sides,
// making neighboring cards look like they overlap empty space rather than
// actual photo content. The ring's spacing cadence (stepOffsetX) still uses
// one fixed reference width (the average of a typical portrait and
// landscape card) rather than a true per-pair variable step, since the
// continuous sliding-phase math assumes uniform spacing — close enough for
// a decorative carousel without needing a fully variable-width ring.
//
// Images come from two sources, additively:
// - `stockImageNames`: a couple of images bundled in Assets.xcassets,
//   rendered synchronously (no network, no loading state) so the ring is
//   never empty/placeholder-only on first appear, however slow or flaky the
//   network is.
// - `imageNames`: the public "carousel_postcards" Supabase Storage bucket
//   (not bundled, so the same sample set can be reused by the web landing
//   page later without duplicating files per platform) — these load
//   asynchronously and are appended to the ring once fetched. Public URL is
//   hand-built the same way CardUploadService does for the "card-images"
//   bucket — this codebase doesn't use the SDK's getPublicURL() anywhere, so
//   this matches the established convention.
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
    var secondsPerCard: Double = 10.0          // time for the ring to advance by one slot
    var overlapFraction: CGFloat = 0.125       // 12.5% — within the requested 10-15% range
    var anglePerStep: Double = 14              // degrees of tilt per slot away from center
    var scaleFalloffPerStep: CGFloat = 0.12
    var viewportWidthMultiplier: CGFloat = 1.7 // how much of each side neighbor peeks past the front card
    var maxCardWidth: CGFloat = .infinity       // the actual device screen width — no single card can render wider than this

    @State private var startDate = Date()
    // Each card's actual rendered width, keyed by image name, measured once
    // its image loads and sizes itself to its own native aspect ratio.
    @State private var measuredWidths: [String: CGFloat] = [:]

    // Used for spacing cadence only (not any individual card's own frame) —
    // the midpoint between a typical portrait and landscape card's width.
    private var referenceWidth: CGFloat {
        cardHeight * (portraitAspectRatio + landscapeAspectRatio) / 2
    }
    private var stepOffsetX: CGFloat { referenceWidth * (1 - overlapFraction) }

    // Stock images first, bucket images appended once loaded — stock alone
    // is always enough to fill the ring, so there's never an empty/
    // placeholder-only moment while the bucket fetch is in flight.
    private var sources: [CardImageSource] {
        stockImageNames.map { .stock($0) } + imageNames.map { .remote($0) }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = phase(at: timeline.date)
            ZStack {
                ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                    let delta = wrappedDelta(Double(index), phase: phase, count: sources.count)
                    cardView(source)
                        .rotationEffect(.degrees(delta * anglePerStep))
                        .scaleEffect(scale(for: delta))
                        .offset(x: delta * stepOffsetX)
                        // Signed (not absolute) so the right card in any
                        // overlapping pair is always on top of the one to
                        // its left, consistently — abs(delta) gave left
                        // and right neighbors at the same distance an
                        // identical z-index, so their relative stacking
                        // order was undefined and could flip mid-animation.
                        .zIndex(delta)
                }
            }
        }
        .frame(width: referenceWidth * viewportWidthMultiplier, height: cardHeight * 1.2)
        .clipped()
    }

    private func phase(at date: Date) -> Double {
        guard secondsPerCard > 0 else { return 0 }
        return date.timeIntervalSince(startDate) / secondsPerCard
    }

    private func wrappedDelta(_ i: Double, phase: Double, count: Int) -> Double {
        guard count > 0 else { return 0 }
        let n = Double(count)
        var d = (i - phase).truncatingRemainder(dividingBy: n)
        if d > n / 2 { d -= n }
        if d < -n / 2 { d += n }
        return d
    }

    private func scale(for delta: Double) -> CGFloat {
        max(0.55, 1 - CGFloat(abs(delta)) * scaleFalloffPerStep)
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
        // Capped at the actual device screen width so no single card —
        // regardless of source or measured aspect ratio — can ever render
        // wider than the viewport.
        let width = min(measuredWidths[key] ?? referenceWidth, maxCardWidth)

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
                .frame(width: width, height: cardHeight)
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
                        .frame(width: width, height: cardHeight)
                        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                default:
                    // Covers both the loading and failure cases — keeps the
                    // ring visually complete instead of rendering a blank
                    // gap (the stock images already guarantee the ring
                    // isn't empty, this just covers a slow/failed bucket
                    // fetch for this particular slot).
                    RoundedRectangle(cornerRadius: cardCornerRadius)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: width, height: cardHeight)
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
