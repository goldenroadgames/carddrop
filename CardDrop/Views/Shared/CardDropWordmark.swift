import SwiftUI

// The "CardDrop" wordmark is brand identity, not body text — unlike the
// rest of the app (plain .system() fonts throughout), it renders in a
// specific bundled typeface (Inter ExtraBold) so it looks identical
// wherever it appears, rather than varying with whatever the OS's default
// system font happens to be. Font.custom(name:size:) doesn't reliably size
// a custom font when passed a plain SwiftUI Font value in some contexts
// (see [[feedback_imagerenderer_custom_font]]) — resolving a concrete
// UIFont and wrapping it as Font(uiFont) is the reliable path.
struct CardDropWordmark: View {
    var size: CGFloat = 34  // .largeTitle-equivalent point size
    var dropOffset: CGFloat = 8
    var color: Color = .brandBlue

    private var font: Font {
        Font(UIFont(name: "Inter-ExtraBold", size: size) ?? UIFont.boldSystemFont(ofSize: size))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("Card")
                .font(font)
                .foregroundColor(color)
            Text("Drop")
                .font(font)
                .foregroundColor(color)
                .offset(y: dropOffset)
        }
    }
}

#Preview {
    CardDropWordmark()
}
