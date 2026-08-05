import SwiftUI

struct CardDropWordmark: View {
    var font: Font = .largeTitle.bold()
    var dropOffset: CGFloat = 8
    var color: Color = .brandBlue

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
