import SwiftUI

/// A plain, two-tone (white + brand blue) mocked-up "Greetings From" postcard,
/// used as decoration on the nickname step. Kept simple/flat to blend into the UI.
struct GreetingsPostcardGraphic: View {
    var body: some View {
        ZStack {
            // Back card, peeking out behind the front card
            Rectangle()
                .fill(Color.white)
                .frame(width: 222, height: 150)
                .overlay(
                    Rectangle()
                        .stroke(Color.brandBlue, lineWidth: 2)
                )
                .overlay(backCardContent)
                .rotationEffect(.degrees(9))
                .offset(x: 33, y: -18)

            // Front card
            Rectangle()
                .fill(Color.white)
                .frame(width: 234, height: 162)
                .overlay(
                    Rectangle()
                        .stroke(Color.brandBlue, lineWidth: 2)
                )
                .overlay(frontCardContent)
                .rotationEffect(.degrees(-7))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }
        .frame(height: 198)
    }

    // MARK: - Back card (address-side sliver)

    private var backCardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                sun(size: 30, rayLength: 6, rayWidth: 1.5)
            }
            Rectangle().fill(Color.brandBlue.opacity(0.5)).frame(height: 1)
            ForEach(0..<3, id: \.self) { _ in
                Rectangle().fill(Color.gray.opacity(0.4)).frame(height: 1)
            }
        }
        .padding(15)
    }

    // MARK: - Front card

    private var frontCardContent: some View {
        ZStack(alignment: .bottomTrailing) {
            sun(size: 52, rayLength: 10, rayWidth: 2.5)
                .offset(x: -34, y: -16)

            Text("Greetings")
                .font(.custom("SnellRoundhand-Bold", size: 58))
                .foregroundColor(.brandBlue)
                .rotationEffect(.degrees(-18))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: 4, y: 22)

            Text("from")
                .font(.custom("SnellRoundhand-Bold", size: 42))
                .foregroundColor(.brandBlue)
                .rotationEffect(.degrees(-18))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: 44, y: 78)
        }
        .clipShape(Rectangle())
    }

    // MARK: - Sun (rays + circle)

    private func sun(size: CGFloat, rayLength: CGFloat, rayWidth: CGFloat) -> some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Rectangle()
                    .fill(Color.brandBlue.opacity(0.45))
                    .frame(width: rayWidth, height: rayLength)
                    .offset(y: -(size / 2))
                    .rotationEffect(.degrees(Double(i) * 45))
            }
            Circle()
                .fill(Color.brandBlue.opacity(0.2))
                .overlay(Circle().stroke(Color.brandBlue, lineWidth: 1.5))
                .frame(width: size * 0.55, height: size * 0.55)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    GreetingsPostcardGraphic()
        .padding(40)
}
