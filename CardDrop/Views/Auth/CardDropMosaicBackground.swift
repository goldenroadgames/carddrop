import SwiftUI

// Full-screen tiled background of the "CardDrop" wordmark, in a lightened
// tint, shown behind the landing reveal until the rising content stack
// covers it. One tile — the "anchor" — is placed at EXACTLY the same
// starting position as the real "Card" in the opening beat (not an
// arbitrary grid origin), so the real, full-opacity "Card" sits precisely
// on top of the anchor tile's own "Card" prefix, as if it were emerging
// from the pattern, and stays that way through the fall/bounce until the
// rising real content stack's opaque background sweeps up and covers it.
struct CardDropMosaicBackground: View {
    var viewportSize: CGSize
    var anchor: CGPoint     // top-leading corner of the anchor tile — matches "Card"'s own top-leading corner in the opening beat
    var tileSize: CGSize    // one tile's natural (font-intrinsic) size — pass the same measured width/height as the real "Card"+"Drop" row, since it's the same text at the same font
    var tileFont: Font
    var tint: Color = .brandBlue
    var tileOpacity: Double = 0.2
    var horizontalGap: CGFloat = 60   // extra space between tiles, on top of each tile's own width
    var verticalGap: CGFloat = 80     // extra space between tile rows, on top of each tile's own height

    var body: some View {
        let spacingX = max(tileSize.width, 1) + horizontalGap
        let spacingY = max(tileSize.height, 1) + verticalGap

        // +1 extra column of padding since staggered (odd) rows shift right
        // by half a tile — without it, the left edge of those rows would
        // come up short.
        let columnsBefore = Int(ceil(anchor.x / spacingX)) + 2
        let columnsAfter = Int(ceil((viewportSize.width - anchor.x) / spacingX)) + 1
        let rowsBefore = Int(ceil(anchor.y / spacingY)) + 1
        let rowsAfter = Int(ceil((viewportSize.height - anchor.y) / spacingY)) + 1

        ZStack(alignment: .topLeading) {
            ForEach(-rowsBefore...rowsAfter, id: \.self) { row in
                // Alternate rows: even rows align to the anchor's own
                // column (typically 3 tiles across, edges cut off by the
                // screen); odd rows shift by half a tile-spacing, so their
                // (typically 2) tiles land centered in the gaps between the
                // rows above and below — a brick/checkerboard stagger.
                let rowOffsetX: CGFloat = row.isMultiple(of: 2) ? 0 : spacingX / 2
                ForEach(-columnsBefore...columnsAfter, id: \.self) { col in
                    Text("CardDrop")
                        .font(tileFont)
                        .foregroundColor(tint)
                        .opacity(tileOpacity)
                        .fixedSize()
                        .offset(
                            x: anchor.x + rowOffsetX + CGFloat(col) * spacingX,
                            y: anchor.y + CGFloat(row) * spacingY
                        )
                }
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
    }
}

#Preview {
    CardDropMosaicBackground(
        viewportSize: CGSize(width: 390, height: 844),
        anchor: CGPoint(x: 60, y: 400),
        tileSize: CGSize(width: 160, height: 46),
        tileFont: Font(UIFont(name: "Inter-ExtraBold", size: 38) ?? UIFont.boldSystemFont(ofSize: 38))
    )
}
